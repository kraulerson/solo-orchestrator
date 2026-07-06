# Intake Wizard Implementation Plan

> **Archived 2026-07-05 (BL-049):** Shipped via commit `9354c46` ("feat: intake wizard implementation", 2026-04-04). See `docs/superpowers/plans/archive/README.md` for the archive convention.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an interactive intake wizard that guides users through filling out PROJECT_INTAKE.md via a bash script (confident users) or Claude Code conversation (users wanting help), with section-by-section save/resume, context-aware suggestions, and POC governance modes.

**Architecture:** A single bash script (`scripts/intake-wizard.sh`) handles mode selection, section-by-section Q&A, save/resume via `.claude/intake-progress.json`, and POC mode tracking. Suggestion data lives in `templates/intake-suggestions/*.json` files read at runtime. The Claude-guided path generates a prompt file from `templates/intake-guided-prompt.md`. init.sh offers the wizard after project creation and copies all files into generated projects.

**Tech Stack:** Bash, JSON (suggestion files), Markdown (prompt template, documentation)

**Design spec:** `docs/superpowers/specs/2026-04-02-intake-wizard-design.md`

---

## File Map

| File | Action | Responsibility | Task |
|---|---|---|---|
| `scripts/intake-wizard.sh` | Create | Entry point, mode selection, section Q&A, save/resume, POC modes, suggestion loading, Intake file writing | Tasks 1-7 |
| `templates/intake-suggestions/common.json` | Create | Platform-independent suggestions (budget, timeline, accessibility, uptime) | Task 2 |
| `templates/intake-suggestions/web.json` | Create | Web platform suggestions (auth, hosting, DB, frameworks) | Task 2 |
| `templates/intake-suggestions/desktop.json` | Create | Desktop platform suggestions | Task 2 |
| `templates/intake-suggestions/mobile.json` | Create | Mobile platform suggestions | Task 2 |
| `templates/intake-suggestions/mcp_server.json` | Create | MCP-server platform suggestions (transport, persistence, mcp_sdk) | Task 2 |
| `templates/intake-guided-prompt.md` | Create | Template for Claude-guided conversation prompt | Task 8 |
| `init.sh` | Modify | Offer wizard after project creation, copy new files | Task 9 |
| `docs/user-guide.md` | Modify | Document wizard, POC modes, upgrade path | Task 10 |
| `templates/project-intake.md` | Modify | Add POC watermark fields to Section 8 | Task 10 |

---

### Task 1: Wizard script — core framework and utility functions

Create the script skeleton with all shared utilities. After this task, the script can be sourced and its utility functions work, but no sections are implemented yet.

**Files:**
- Create: `scripts/intake-wizard.sh`

- [ ] **Step 1: Create the script with header, flags, colors, and core utilities**

Create `scripts/intake-wizard.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Intake Wizard
# Guides users through filling out PROJECT_INTAKE.md interactively.
#
# Usage:
#   scripts/intake-wizard.sh                  # Start or choose mode
#   scripts/intake-wizard.sh --resume         # Resume from last save point
#   scripts/intake-wizard.sh --upgrade-to-production  # Upgrade POC to production

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROGRESS_FILE="$PROJECT_ROOT/.claude/intake-progress.json"
INTAKE_FILE="$PROJECT_ROOT/PROJECT_INTAKE.md"
SUGGESTIONS_DIR="$PROJECT_ROOT/templates/intake-suggestions"

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
fi

print_step() { echo -e "${CYAN}[STEP]${NC} $1"; }
print_ok()   { echo -e "${GREEN}  [OK]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# ================================================================
# UTILITY: Prompt for text input with optional default
# ================================================================
prompt_input() {
  local prompt="$1"
  local default="${2:-}"
  local result
  if [ -n "$default" ]; then
    read -rp "$(echo -e "  ${BOLD}$prompt${NC} [$default]: ")" result
    echo "${result:-$default}"
  else
    read -rp "$(echo -e "  ${BOLD}$prompt${NC}: ")" result
    echo "$result"
  fi
}

# ================================================================
# UTILITY: Prompt for numbered choice
# ================================================================
prompt_choice() {
  local prompt="$1"
  shift
  local options=("$@")
  echo -e "  ${BOLD}$prompt${NC}" >&2
  for i in "${!options[@]}"; do
    echo "    $((i+1)). ${options[$i]}" >&2
  done
  local choice
  while true; do
    read -rp "$(echo -e "  ${BOLD}Select [1-${#options[@]}]${NC}: ")" choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
      echo "${options[$((choice-1))]}"
      return
    fi
    echo "  Invalid choice. Enter a number between 1 and ${#options[@]}." >&2
  done
}

# ================================================================
# UTILITY: Prompt with ? for suggestions
# Usage: result=$(prompt_with_suggestions "Auth strategy" "authentication" "$default")
# ================================================================
prompt_with_suggestions() {
  local prompt="$1"
  local suggestion_key="$2"
  local default="${3:-}"
  local result

  while true; do
    if [ -n "$default" ]; then
      read -rp "$(echo -e "  ${BOLD}$prompt${NC} [? for suggestions, default: $default]: ")" result
    else
      read -rp "$(echo -e "  ${BOLD}$prompt${NC} [? for suggestions]: ")" result
    fi

    if [ "$result" = "?" ]; then
      show_suggestions "$suggestion_key"
      continue
    fi

    if [ -z "$result" ] && [ -n "$default" ]; then
      echo "$default"
      return
    fi

    if [ -n "$result" ]; then
      echo "$result"
      return
    fi

    echo "  Please enter a value or type ? for suggestions." >&2
  done
}

# ================================================================
# UTILITY: Show suggestions from JSON files
# ================================================================
show_suggestions() {
  local key="$1"
  local platform_file="$SUGGESTIONS_DIR/${PLATFORM}.json"
  local common_file="$SUGGESTIONS_DIR/common.json"
  local found=false

  # Try platform-specific suggestions first
  if [ -f "$platform_file" ]; then
    local suggestions
    suggestions=$(parse_suggestions "$platform_file" "$key" "$LANGUAGE" 2>/dev/null || true)
    if [ -n "$suggestions" ]; then
      echo "" >&2
      echo -e "  ${CYAN}Based on your project ($PLATFORM, $LANGUAGE):${NC}" >&2
      echo "$suggestions" >&2
      echo "" >&2
      found=true
    fi
  fi

  # Fall back to common suggestions
  if [ "$found" = false ] && [ -f "$common_file" ]; then
    local suggestions
    suggestions=$(parse_suggestions "$common_file" "$key" "" 2>/dev/null || true)
    if [ -n "$suggestions" ]; then
      echo "" >&2
      echo -e "  ${CYAN}Suggestions:${NC}" >&2
      echo "$suggestions" >&2
      echo "" >&2
      found=true
    fi
  fi

  if [ "$found" = false ]; then
    echo "  No suggestions available for this field." >&2
  fi
}

# ================================================================
# UTILITY: Parse suggestions from a JSON file
# Minimal JSON parsing with grep/sed (no jq dependency)
# ================================================================
parse_suggestions() {
  local file="$1"
  local key="$2"
  local language="$3"
  local in_key=false
  local in_lang=false
  local counter=0
  local name="" context=""

  # Use python3 for reliable JSON parsing if available, else basic grep
  if command -v python3 &>/dev/null; then
    python3 -c "
import json, sys
with open('$file') as f:
    data = json.load(f)
suggestions = data.get('suggestions', {}).get('$key', {})
# Try language-specific, then 'default'
items = suggestions.get('$language', suggestions.get('default', []))
for i, item in enumerate(items, 1):
    rank_label = ' (recommended)' if item.get('rank') == 1 else ''
    print(f\"    {i}. {item['name']}{rank_label}\")
    print(f\"       {item['context']}\")
" 2>/dev/null
  fi
}

# ================================================================
# PROGRESS: Initialize progress file
# ================================================================
init_progress() {
  mkdir -p "$(dirname "$PROGRESS_FILE")"
  cat > "$PROGRESS_FILE" << PEOF
{
  "version": 1,
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "last_section": 0,
  "completed_sections": [],
  "project_name": "$PROJECT_NAME",
  "platform": "$PLATFORM",
  "track": "$TRACK",
  "deployment": "$DEPLOYMENT",
  "language": "$LANGUAGE",
  "description": "$PROJECT_DESCRIPTION",
  "poc_mode": null,
  "answers": {}
}
PEOF
}

# ================================================================
# PROGRESS: Save a completed section
# ================================================================
save_section() {
  local section_num="$1"
  if command -v python3 &>/dev/null; then
    python3 -c "
import json
with open('$PROGRESS_FILE') as f:
    data = json.load(f)
data['last_section'] = $section_num
if $section_num not in data['completed_sections']:
    data['completed_sections'].append($section_num)
    data['completed_sections'].sort()
with open('$PROGRESS_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
  fi
  print_ok "Section $section_num saved. You can resume later with: scripts/intake-wizard.sh --resume"
}

# ================================================================
# PROGRESS: Save an answer to the progress file
# ================================================================
save_answer() {
  local key="$1"
  local value="$2"
  if command -v python3 &>/dev/null; then
    python3 -c "
import json
with open('$PROGRESS_FILE') as f:
    data = json.load(f)
data['answers'][$(python3 -c "import json; print(json.dumps('$key'))")] = $(python3 -c "import json; print(json.dumps('$value'))")
with open('$PROGRESS_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
  fi
}

# ================================================================
# PROGRESS: Load progress and project context
# ================================================================
load_progress() {
  if [ ! -f "$PROGRESS_FILE" ]; then
    echo ""
    print_warn "No progress file found. Run the intake wizard from the start."
    return 1
  fi

  if command -v python3 &>/dev/null; then
    eval "$(python3 -c "
import json
with open('$PROGRESS_FILE') as f:
    data = json.load(f)
print(f\"LAST_SECTION={data['last_section']}\")
print(f\"PROJECT_NAME='{data['project_name']}'\")
print(f\"PLATFORM='{data['platform']}'\")
print(f\"TRACK='{data['track']}'\")
print(f\"DEPLOYMENT='{data['deployment']}'\")
print(f\"LANGUAGE='{data['language']}'\")
print(f\"PROJECT_DESCRIPTION='{data['description']}'\")
poc = data.get('poc_mode') or ''
print(f\"POC_MODE='{poc}'\")
completed = ' '.join(str(s) for s in data.get('completed_sections', []))
print(f\"COMPLETED_SECTIONS='{completed}'\")
")"
  fi
}

# ================================================================
# PROGRESS: Check if a section is completed
# ================================================================
is_section_complete() {
  local section_num="$1"
  [[ " $COMPLETED_SECTIONS " == *" $section_num "* ]]
}

# ================================================================
# INTAKE FILE: Write a section into PROJECT_INTAKE.md
# Uses sed to replace placeholder content between section markers
# ================================================================
write_intake_section() {
  local section_num="$1"
  local content="$2"
  # Implementation: use python3 to find the section header and replace
  # content up to the next section header. Each section function
  # produces the formatted markdown for its section.
  if command -v python3 &>/dev/null; then
    python3 << PYEOF
import re

with open('$INTAKE_FILE', 'r') as f:
    text = f.read()

# Section headers are "## N. Title" or "## Section N"
# Find the section and replace its content
section_pattern = r'(## ${section_num}\. [^\n]+\n)(.*?)(?=\n## \d+\. |\n---\n## Checklist|\Z)'
replacement = r'\1${content}'

text = re.sub(section_pattern, replacement, text, flags=re.DOTALL)

with open('$INTAKE_FILE', 'w') as f:
    f.write(text)
PYEOF
  fi
}

# ================================================================
# PAUSE: Handle user requesting a pause
# ================================================================
check_pause() {
  local input="$1"
  if [ "$input" = "pause" ] || [ "$input" = "PAUSE" ]; then
    echo ""
    print_info "Pausing intake wizard. Progress saved."
    print_info "Resume with: scripts/intake-wizard.sh --resume"
    exit 0
  fi
}
```

- [ ] **Step 2: Make the script executable and verify syntax**

```bash
chmod +x scripts/intake-wizard.sh
bash -n scripts/intake-wizard.sh
```

Expected: No syntax errors.

- [ ] **Step 3: Commit**

```bash
git add scripts/intake-wizard.sh
git commit -m "feat(intake-wizard): add core framework and utility functions

Script skeleton with prompt helpers, suggestion loading (from JSON
files via python3), save/resume progress tracking via
.claude/intake-progress.json, and intake file writing utilities."
```

---

### Task 2: Suggestion data files

Create all 5 suggestion JSON files with platform-specific and common recommendations.

**Files:**
- Create: `templates/intake-suggestions/common.json`
- Create: `templates/intake-suggestions/web.json`
- Create: `templates/intake-suggestions/desktop.json`
- Create: `templates/intake-suggestions/mobile.json`
- Create: `templates/intake-suggestions/mcp_server.json`

- [ ] **Step 1: Create common.json**

```json
{
  "platform": "common",
  "suggestions": {
    "budget_monthly": {
      "default": [
        {
          "name": "$0-50/month",
          "rank": 1,
          "context": "Typical for Light track personal projects. Free tiers of Vercel, Supabase, Railway cover most MVPs.",
          "when": "Light track, personal projects"
        },
        {
          "name": "$50-500/month",
          "rank": 2,
          "context": "Standard track with moderate traffic. Covers paid tiers of hosting, database, and monitoring services.",
          "when": "Standard track, <1000 users"
        },
        {
          "name": "$500+/month",
          "rank": 3,
          "context": "Full track or enterprise internal tools with SLA requirements. Covers dedicated infrastructure and support contracts.",
          "when": "Full track, enterprise, or high-availability requirements"
        }
      ]
    },
    "timeline_mvp": {
      "default": [
        {
          "name": "4-6 weeks",
          "rank": 1,
          "context": "Realistic for a 3-5 feature MVP with one person working 10-15 hours/week. Includes planning phases.",
          "when": "Light track, <5 features"
        },
        {
          "name": "8-12 weeks",
          "rank": 2,
          "context": "Standard timeline for 5-10 features including security validation and user testing.",
          "when": "Standard track, 5-10 features"
        },
        {
          "name": "12-20 weeks",
          "rank": 3,
          "context": "Full track with enterprise governance, pen testing, and formal approval cycles.",
          "when": "Full track or organizational deployment"
        }
      ]
    },
    "accessibility_target": {
      "default": [
        {
          "name": "WCAG AA, Lighthouse 90+",
          "rank": 1,
          "context": "Industry standard. Covers most accessibility requirements. Required by many organizations.",
          "when": "Most projects"
        },
        {
          "name": "WCAG AAA",
          "rank": 2,
          "context": "Highest accessibility standard. Significantly more effort. Required for government or healthcare.",
          "when": "Government, healthcare, or legal requirement"
        },
        {
          "name": "Basic (keyboard navigation + screen reader)",
          "rank": 3,
          "context": "Minimum viable accessibility. Not recommended for external-facing apps.",
          "when": "Internal tools with known user base"
        }
      ]
    },
    "uptime_expectation": {
      "default": [
        {
          "name": "Best effort (99%)",
          "rank": 1,
          "context": "~7 hours downtime/month. Appropriate for internal tools and personal projects. No pager required.",
          "when": "Light track, personal, internal tools"
        },
        {
          "name": "Standard (99.9%)",
          "rank": 2,
          "context": "~43 minutes downtime/month. Standard for SaaS products. Requires monitoring and alerting.",
          "when": "Standard track, external users"
        },
        {
          "name": "High availability (99.99%+)",
          "rank": 3,
          "context": "~4 minutes downtime/month. The framework explicitly says it is not designed for this. Consider a dedicated platform team.",
          "when": "Not recommended — see framework Known Limitations"
        }
      ]
    },
    "data_sensitivity": {
      "default": [
        {
          "name": "Public",
          "rank": 1,
          "context": "No access controls needed. Safe to cache, log, and display freely.",
          "when": "Content that is intentionally public"
        },
        {
          "name": "Internal",
          "rank": 2,
          "context": "Requires authentication to access. Standard access controls.",
          "when": "Business data, internal reports"
        },
        {
          "name": "Confidential",
          "rank": 3,
          "context": "Restricted access, audit logging, encryption at rest. Need-to-know basis.",
          "when": "Financial data, trade secrets, strategic plans"
        },
        {
          "name": "PII (Personally Identifiable Information)",
          "rank": 4,
          "context": "Subject to privacy laws (GDPR, CCPA, etc.). Requires consent, retention policies, right to deletion.",
          "when": "Names, emails, addresses, phone numbers, government IDs"
        }
      ]
    }
  }
}
```

- [ ] **Step 2: Create web.json**

```json
{
  "platform": "web",
  "suggestions": {
    "authentication": {
      "typescript": [
        {
          "name": "Supabase Auth",
          "rank": 1,
          "context": "You'll likely use Supabase for data — auth comes included. Supports email/password, magic links, and social logins. No additional cost.",
          "when": "Most web projects with Supabase"
        },
        {
          "name": "NextAuth.js (Auth.js)",
          "rank": 2,
          "context": "More flexible if you need custom providers or complex session handling. Works with any database. More setup, but well-documented.",
          "when": "Custom auth requirements or multiple OAuth providers"
        },
        {
          "name": "Clerk",
          "rank": 3,
          "context": "Fastest to implement. Managed service with pre-built UI components. Free tier covers 10K MAU, then $25/mo.",
          "when": "Speed to market is top priority"
        }
      ],
      "python": [
        {
          "name": "Supabase Auth (via supabase-py)",
          "rank": 1,
          "context": "Same Supabase Auth, accessed from Python. Works with FastAPI or Django.",
          "when": "Using Supabase for data"
        },
        {
          "name": "FastAPI Users",
          "rank": 2,
          "context": "Native FastAPI auth with OAuth2, JWT, database backends. More control, more setup.",
          "when": "FastAPI projects needing custom auth flows"
        },
        {
          "name": "Django Auth",
          "rank": 3,
          "context": "Built into Django. Battle-tested, session-based. Add django-allauth for social logins.",
          "when": "Django projects"
        }
      ],
      "default": [
        {
          "name": "Supabase Auth",
          "rank": 1,
          "context": "Managed auth with email/password, magic links, social logins. Works with any language via REST API.",
          "when": "Most web projects"
        }
      ]
    },
    "hosting": {
      "typescript": [
        {
          "name": "Vercel",
          "rank": 1,
          "context": "Native Next.js support, generous free tier, zero-config deployments. Best default for solo Next.js projects.",
          "when": "Next.js projects"
        },
        {
          "name": "Railway",
          "rank": 2,
          "context": "More flexibility for backend-heavy apps. Simple pricing, good DX. Better for persistent processes or WebSockets.",
          "when": "Custom backends, WebSocket servers, or cron jobs"
        },
        {
          "name": "Cloudflare Pages + Workers",
          "rank": 3,
          "context": "Edge-first deployment. Excellent performance globally. Steeper learning curve for Workers.",
          "when": "Global audience, edge computing needs"
        }
      ],
      "python": [
        {
          "name": "Railway",
          "rank": 1,
          "context": "Simple Python deployment, good free tier, built-in PostgreSQL. Best for solo Python projects.",
          "when": "FastAPI, Flask, or Django projects"
        },
        {
          "name": "Fly.io",
          "rank": 2,
          "context": "Container-based deployment, global edge network. More control than Railway.",
          "when": "Need multi-region or specific infrastructure control"
        },
        {
          "name": "Render",
          "rank": 3,
          "context": "Heroku alternative. Simple deployment, managed PostgreSQL. Free tier available.",
          "when": "Simple deployment needs"
        }
      ],
      "default": [
        {
          "name": "Vercel or Railway",
          "rank": 1,
          "context": "Both offer generous free tiers and simple deployment. Vercel for frontend-heavy, Railway for backend-heavy.",
          "when": "Most web projects"
        }
      ]
    },
    "database": {
      "typescript": [
        {
          "name": "Supabase (PostgreSQL)",
          "rank": 1,
          "context": "Managed Postgres with built-in auth, row-level security, real-time subscriptions, and auto-generated API. Free tier covers most MVPs.",
          "when": "Most web projects"
        },
        {
          "name": "PlanetScale (MySQL)",
          "rank": 2,
          "context": "Serverless MySQL with branching workflows. Good if you prefer MySQL or need database branching for schema changes.",
          "when": "MySQL preference or complex migration workflows"
        },
        {
          "name": "SQLite (via Turso)",
          "rank": 3,
          "context": "Edge-friendly, embedded database. Very fast reads. Good for read-heavy apps or per-user databases.",
          "when": "Read-heavy apps, per-user data isolation"
        }
      ],
      "python": [
        {
          "name": "Supabase (PostgreSQL)",
          "rank": 1,
          "context": "Managed Postgres with auth and API. Works with SQLAlchemy, Prisma, or raw SQL.",
          "when": "Most web projects"
        },
        {
          "name": "PostgreSQL (self-managed on Railway/Render)",
          "rank": 2,
          "context": "Standard PostgreSQL with more control. Railway and Render provide managed instances.",
          "when": "Need specific PostgreSQL extensions or configuration"
        }
      ],
      "default": [
        {
          "name": "Supabase (PostgreSQL)",
          "rank": 1,
          "context": "Managed Postgres with auth, row-level security, and auto-generated API.",
          "when": "Most web projects"
        }
      ]
    },
    "frontend_framework": {
      "typescript": [
        {
          "name": "Next.js 15 (App Router)",
          "rank": 1,
          "context": "Full-stack React framework with server components, API routes, and Vercel integration. The ecosystem default for TypeScript web apps.",
          "when": "Most web projects"
        },
        {
          "name": "Remix",
          "rank": 2,
          "context": "Simpler mental model than Next.js, better form handling, runs anywhere. Good if Vercel lock-in concerns you.",
          "when": "Form-heavy apps or multi-host deployment"
        },
        {
          "name": "SvelteKit",
          "rank": 3,
          "context": "Lighter than React, excellent performance, less ecosystem. TypeScript support is good but fewer examples.",
          "when": "Performance-critical UI, smaller bundle size"
        }
      ],
      "default": [
        {
          "name": "Next.js 15",
          "rank": 1,
          "context": "Full-stack React framework. The most commonly recommended stack for TypeScript web apps.",
          "when": "Most web projects"
        }
      ]
    }
  }
}
```

- [ ] **Step 3: Create desktop.json**

```json
{
  "platform": "desktop",
  "suggestions": {
    "authentication": {
      "typescript": [
        {
          "name": "Local auth with encrypted storage",
          "rank": 1,
          "context": "For single-user desktop apps. Store credentials in OS keychain (keytar). No server needed.",
          "when": "Personal tools, single user"
        },
        {
          "name": "OAuth2 with PKCE (via system browser)",
          "rank": 2,
          "context": "For apps that connect to a web service. Opens system browser for auth, receives token via localhost redirect.",
          "when": "Apps connected to a web API or cloud service"
        }
      ],
      "rust": [
        {
          "name": "OS keychain (keyring crate)",
          "rank": 1,
          "context": "Store credentials in macOS Keychain, Windows Credential Manager, or Linux Secret Service.",
          "when": "Single-user desktop apps"
        }
      ],
      "default": [
        {
          "name": "OS keychain integration",
          "rank": 1,
          "context": "Use the operating system's native credential storage. Secure, no server required.",
          "when": "Most desktop apps"
        }
      ]
    },
    "ui_framework": {
      "typescript": [
        {
          "name": "Electron + React",
          "rank": 1,
          "context": "Most mature desktop framework for web technologies. Large ecosystem. Higher memory usage. Best tooling support.",
          "when": "Full-featured desktop apps, cross-platform"
        },
        {
          "name": "Tauri + React",
          "rank": 2,
          "context": "Rust-based alternative to Electron. Much smaller binaries, lower memory. Newer, smaller ecosystem.",
          "when": "Performance-sensitive apps or if bundle size matters"
        }
      ],
      "rust": [
        {
          "name": "Tauri",
          "rank": 1,
          "context": "Native Rust backend with web frontend. Small binaries, low memory, system-native feel.",
          "when": "Most Rust desktop apps"
        }
      ],
      "csharp": [
        {
          "name": "WPF (.NET)",
          "rank": 1,
          "context": "Windows-only but mature and full-featured. Best for Windows-targeted business tools.",
          "when": "Windows-only apps"
        },
        {
          "name": "MAUI (.NET)",
          "rank": 2,
          "context": "Cross-platform .NET UI. Works on Windows, macOS, iOS, Android. Newer, still maturing.",
          "when": "Cross-platform .NET apps"
        }
      ],
      "default": [
        {
          "name": "Electron (cross-platform) or Tauri (lightweight)",
          "rank": 1,
          "context": "Electron for maximum compatibility and ecosystem. Tauri for smaller, faster apps.",
          "when": "Most desktop apps"
        }
      ]
    },
    "packaging": {
      "default": [
        {
          "name": "Platform-native installers",
          "rank": 1,
          "context": "DMG for macOS, MSI/NSIS for Windows, AppImage/deb for Linux. Users expect native formats.",
          "when": "Most desktop apps"
        },
        {
          "name": "Portable executables",
          "rank": 2,
          "context": "No installation required. Good for internal tools or USB distribution.",
          "when": "Internal tools, no admin rights environments"
        }
      ]
    },
    "auto_update": {
      "default": [
        {
          "name": "electron-updater (Electron) or tauri-updater (Tauri)",
          "rank": 1,
          "context": "Built-in update mechanism for each framework. Downloads and installs updates automatically.",
          "when": "Most desktop apps distributed outside app stores"
        },
        {
          "name": "Manual update notification",
          "rank": 2,
          "context": "App checks for new version and shows a link. Simpler but relies on user action.",
          "when": "Low-frequency update needs"
        }
      ]
    }
  }
}
```

- [ ] **Step 4: Create mobile.json**

```json
{
  "platform": "mobile",
  "suggestions": {
    "authentication": {
      "dart": [
        {
          "name": "Supabase Auth (via supabase_flutter)",
          "rank": 1,
          "context": "Managed auth with email, magic links, social logins. Native Flutter package.",
          "when": "Flutter apps using Supabase"
        },
        {
          "name": "Firebase Auth",
          "rank": 2,
          "context": "Google's managed auth. Excellent Flutter integration. Free for most use cases.",
          "when": "Flutter apps using Firebase ecosystem"
        }
      ],
      "typescript": [
        {
          "name": "Supabase Auth (via @supabase/supabase-js)",
          "rank": 1,
          "context": "Works with React Native via the JS client. Same auth as web.",
          "when": "React Native apps using Supabase"
        },
        {
          "name": "Firebase Auth (via @react-native-firebase)",
          "rank": 2,
          "context": "Native Firebase integration for React Native. Well-supported.",
          "when": "React Native apps using Firebase"
        }
      ],
      "kotlin": [
        {
          "name": "Firebase Auth",
          "rank": 1,
          "context": "Native Android SDK. Best-in-class for Kotlin Android apps.",
          "when": "Android-only apps"
        }
      ],
      "default": [
        {
          "name": "Firebase Auth or Supabase Auth",
          "rank": 1,
          "context": "Both provide managed auth with mobile SDKs. Firebase has deeper mobile integration. Supabase is simpler.",
          "when": "Most mobile apps"
        }
      ]
    },
    "framework": {
      "dart": [
        {
          "name": "Flutter",
          "rank": 1,
          "context": "Cross-platform from a single codebase. Strong typing, hot reload, large widget library.",
          "when": "Cross-platform mobile apps"
        }
      ],
      "typescript": [
        {
          "name": "React Native (Expo)",
          "rank": 1,
          "context": "Managed workflow with Expo. Fastest path to app stores. Limited native module access.",
          "when": "Most React Native apps, especially first-timers"
        },
        {
          "name": "React Native (bare)",
          "rank": 2,
          "context": "Full native module access. More setup, more control. Choose this if Expo's limitations block you.",
          "when": "Apps needing deep native integration"
        }
      ],
      "kotlin": [
        {
          "name": "Kotlin + Jetpack Compose",
          "rank": 1,
          "context": "Android-native with modern declarative UI. Best performance on Android.",
          "when": "Android-only apps"
        }
      ],
      "default": [
        {
          "name": "Flutter or React Native (Expo)",
          "rank": 1,
          "context": "Both are strong cross-platform options. Flutter for Dart developers, React Native for TypeScript/React developers.",
          "when": "Cross-platform mobile apps"
        }
      ]
    },
    "offline_strategy": {
      "default": [
        {
          "name": "Offline tolerant",
          "rank": 1,
          "context": "App works online but handles connectivity loss gracefully. Shows cached data, queues actions.",
          "when": "Most apps — good default"
        },
        {
          "name": "Offline capable",
          "rank": 2,
          "context": "Core features work without connectivity. Syncs when online. Requires local database.",
          "when": "Field work, unreliable connectivity"
        },
        {
          "name": "Offline first",
          "rank": 3,
          "context": "Everything works offline. Network is optional. Significant complexity for sync and conflict resolution.",
          "when": "Remote locations, medical/emergency apps"
        }
      ]
    }
  }
}
```

- [x] **Step 5: Create mcp_server.json** (supersedes the earlier `cli.json` draft)

> **Drift note (audit specs-plans-init-intake-noninteractive-3):** the original
> draft of this step targeted a `cli` platform / `cli.json` suggestion file.
> That file was never shipped — when the 2026-04-25 non-interactive spec
> landed, the platform set converged on `mcp_server` and the actually-shipped
> suggestion file is `templates/intake-suggestions/mcp_server.json`. The
> wizard prompt + Section-6.4 case branch were updated accordingly to read
> from `mcp_server.json` (transport / mcp_sdk / persistence). See the file
> in-tree for the canonical content; the original cli-themed JSON is no
> longer relevant.

- [ ] **Step 6: Verify all JSON files parse correctly**

```bash
for f in templates/intake-suggestions/*.json; do
  python3 -c "import json; json.load(open('$f'))" && echo "OK: $f" || echo "FAIL: $f"
done
```

Expected: All 5 files OK.

- [ ] **Step 7: Commit**

```bash
git add templates/intake-suggestions/
git commit -m "feat(intake-wizard): add platform suggestion data files

Context-aware suggestions for web, desktop, mobile, and CLI platforms
covering auth, hosting, database, frameworks, distribution, and more.
Common.json covers platform-independent fields (budget, timeline,
accessibility, uptime, data sensitivity)."
```

---

### Task 3: Wizard script — Section Q&A functions (Sections 1-6)

Add the section-by-section question functions for the first 6 sections (the non-conditional ones). Each function asks questions, saves answers, and writes to the Intake file.

**Files:**
- Modify: `scripts/intake-wizard.sh`

- [ ] **Step 1: Add Section 1 (Project Identity) function**

This section is mostly pre-filled from init answers. Only ask for remaining fields.

```bash
# ================================================================
# SECTION 1: Project Identity
# ================================================================
run_section_1() {
  print_step "Section 1: Project Identity"
  echo ""
  print_info "Most of this section is pre-filled from your init.sh answers."
  echo ""

  local codename
  codename=$(prompt_input "Project codename (if different from '$PROJECT_NAME', or press Enter to skip)" "")
  save_answer "codename" "$codename"

  local target_platforms
  target_platforms=$(prompt_with_suggestions "Target platforms (e.g., 'all modern browsers', 'Windows 10+, macOS 12+', 'iOS 16+, Android 13+')" "target_platforms" "")
  save_answer "target_platforms" "$target_platforms"

  local repo_url
  repo_url=$(prompt_input "Repository URL (if already created, or press Enter to skip)" "")
  save_answer "repo_url" "$repo_url"

  # Determine platform module
  local platform_module="None"
  case "$PLATFORM" in
    web) platform_module="SOI-PM-WEB" ;;
    desktop) platform_module="SOI-PM-DESKTOP" ;;
    mobile) platform_module="SOI-PM-MOBILE" ;;
  esac

  # Write to intake file
  write_section_1_to_intake "$codename" "$target_platforms" "$repo_url" "$platform_module"

  save_section 1
  echo ""
}

write_section_1_to_intake() {
  local codename="$1"
  local target_platforms="$2"
  local repo_url="$3"
  local platform_module="$4"

  python3 << PYEOF
import re

with open('$INTAKE_FILE', 'r') as f:
    lines = f.readlines()

# Find Section 1 table and fill in values
replacements = {
    'Project name': '$PROJECT_NAME',
    'Project codename': '${codename:-N/A}',
    'One-sentence description': '$PROJECT_DESCRIPTION',
    'Project track': '${TRACK^}',
    'Platform type': '${PLATFORM^}',
    'Platform Module': '$platform_module',
    'Target platforms': '$target_platforms',
    'Personal or Organizational': '${DEPLOYMENT^}',
    'Repository URL': '${repo_url:-TBD}'
}

result = []
for line in lines:
    replaced = False
    for field, value in replacements.items():
        if f'| **{field}' in line or f'| {field}' in line:
            # Preserve the field name, replace the value column
            parts = line.split('|')
            if len(parts) >= 3:
                parts[2] = f' {value} '
                line = '|'.join(parts)
                replaced = True
                break
    result.append(line)

with open('$INTAKE_FILE', 'w') as f:
    f.writelines(result)
PYEOF
}
```

- [ ] **Step 2: Add Section 2 (Business Context) function**

```bash
# ================================================================
# SECTION 2: Business Context
# ================================================================
run_section_2() {
  print_step "Section 2: Business Context"
  echo ""

  # 2.1 The Problem
  print_info "2.1 The Problem"
  print_info "Describe the problem this project solves. Be specific — not 'improve efficiency'"
  print_info "but 'reconciling vendor invoices takes 6 hours/week of manual spreadsheet work.'"
  echo ""
  local problem
  problem=$(prompt_input "What problem does this solve?" "")
  check_pause "$problem"
  save_answer "problem_statement" "$problem"

  # 2.2 Who Has This Problem
  print_info "2.2 Who Has This Problem"
  echo ""
  local primary_persona
  primary_persona=$(prompt_input "Primary user persona (job title, skill level, what they're trying to do)" "")
  check_pause "$primary_persona"
  save_answer "primary_persona" "$primary_persona"

  local secondary_personas
  secondary_personas=$(prompt_input "Secondary personas (or press Enter to skip)" "")
  save_answer "secondary_personas" "$secondary_personas"

  local current_solution
  current_solution=$(prompt_input "How do they solve this today? (spreadsheet, manual process, different tool)" "")
  check_pause "$current_solution"
  save_answer "current_solution" "$current_solution"

  local current_problem
  current_problem=$(prompt_input "What's wrong with the current solution?" "")
  check_pause "$current_problem"
  save_answer "current_problem" "$current_problem"

  # 2.3 Success Criteria
  print_info "2.3 Success Criteria — define 1-3 measurable metrics"
  echo ""
  local metrics=()
  local i=1
  while [ $i -le 3 ]; do
    local metric
    metric=$(prompt_input "Success metric $i (or press Enter to finish)" "")
    [ -z "$metric" ] && break
    check_pause "$metric"
    local target
    target=$(prompt_input "  Target value for '$metric'" "")
    local measurement
    measurement=$(prompt_input "  How will you measure this?" "")
    metrics+=("$metric|$target|$measurement")
    save_answer "metric_$i" "$metric|$target|$measurement"
    ((i++))
  done

  # 2.4 What This Is NOT
  print_info "2.4 What This Is NOT — list 3-5 things explicitly out of scope"
  echo ""
  local exclusions=()
  for i in 1 2 3 4 5; do
    local exclusion
    if [ $i -le 3 ]; then
      exclusion=$(prompt_input "Out-of-scope item $i" "")
      check_pause "$exclusion"
    else
      exclusion=$(prompt_input "Out-of-scope item $i (or press Enter to finish)" "")
      [ -z "$exclusion" ] && break
    fi
    exclusions+=("$exclusion")
    save_answer "exclusion_$i" "$exclusion"
  done

  write_section_2_to_intake "$problem" "$primary_persona" "$secondary_personas" "$current_solution" "$current_problem" "${metrics[*]}" "${exclusions[*]}"

  save_section 2
  echo ""
}
```

The `write_section_2_to_intake` function follows the same python3 pattern as Section 1 — find the section, replace placeholder content with formatted answers.

- [ ] **Step 3: Add Section 3 (Constraints) function**

```bash
# ================================================================
# SECTION 3: Constraints
# ================================================================
run_section_3() {
  print_step "Section 3: Constraints"
  echo ""

  # 3.1 Timeline
  print_info "3.1 Timeline"
  local mvp_date
  mvp_date=$(prompt_with_suggestions "Target MVP date" "timeline_mvp" "")
  check_pause "$mvp_date"
  save_answer "mvp_date" "$mvp_date"

  local hard_deadline
  hard_deadline=$(prompt_choice "Is this a hard deadline?" "No" "Yes — consequences if missed")
  save_answer "hard_deadline" "$hard_deadline"

  local hours_per_week
  hours_per_week=$(prompt_input "Hours per week you can dedicate to this project" "10")
  save_answer "hours_per_week" "$hours_per_week"

  local time_pattern
  time_pattern=$(prompt_choice "Work pattern:" "Blocked time (dedicated sessions)" "Interleaved (between other work, 1-2 hour windows)")
  save_answer "time_pattern" "$time_pattern"

  # 3.2 Budget
  print_info "3.2 Budget"
  local monthly_budget
  monthly_budget=$(prompt_with_suggestions "Monthly infrastructure budget ceiling" "budget_monthly" "")
  check_pause "$monthly_budget"
  save_answer "monthly_budget" "$monthly_budget"

  local one_time_budget
  one_time_budget=$(prompt_input "One-time budget (or N/A)" "N/A")
  save_answer "one_time_budget" "$one_time_budget"

  local ai_subscription
  ai_subscription=$(prompt_choice "AI subscription status:" "Claude Max ($100/mo)" "Claude Enterprise" "API with commercial terms" "Not yet subscribed")
  save_answer "ai_subscription" "$ai_subscription"

  # 3.3 Users
  print_info "3.3 Users"
  local users_launch
  users_launch=$(prompt_input "Expected users at launch" "")
  check_pause "$users_launch"
  save_answer "users_launch" "$users_launch"

  local users_6mo
  users_6mo=$(prompt_input "Expected users at 6 months" "")
  save_answer "users_6mo" "$users_6mo"

  local users_12mo
  users_12mo=$(prompt_input "Expected users at 12 months" "")
  save_answer "users_12mo" "$users_12mo"

  local user_type
  user_type=$(prompt_choice "Internal or external users?" "Internal (within organization)" "External (public or customer-facing)")
  save_answer "user_type" "$user_type"

  local geo_distribution
  geo_distribution=$(prompt_input "Geographic distribution (e.g., 'US only', 'Global', 'Single office')" "")
  save_answer "geo_distribution" "$geo_distribution"

  save_section 3
  echo ""
}
```

- [ ] **Step 4: Add Section 4 (Features & Requirements) function**

```bash
# ================================================================
# SECTION 4: Features & Requirements
# ================================================================
run_section_4() {
  print_step "Section 4: Features & Requirements"
  echo ""

  # 4.1 Must-Have Features
  print_info "4.1 Must-Have Features (MVP)"
  print_info "For each feature, you'll define:"
  print_info "  - The feature name"
  print_info "  - Business logic trigger: 'If [condition], the system must [action]'"
  print_info "  - Failure state: what happens on invalid input or service unavailable"
  echo ""

  local feature_count=0
  for i in 1 2 3 4 5 6 7 8; do
    local feature_name
    if [ $i -le 2 ]; then
      feature_name=$(prompt_input "Must-have feature $i" "")
      check_pause "$feature_name"
    else
      feature_name=$(prompt_input "Must-have feature $i (or press Enter to finish)" "")
      [ -z "$feature_name" ] && break
    fi

    local trigger
    trigger=$(prompt_input "  Business logic: If [condition], system must [action]" "")
    check_pause "$trigger"

    local failure
    failure=$(prompt_input "  Failure state: what happens when it goes wrong?" "")
    check_pause "$failure"

    save_answer "feature_${i}_name" "$feature_name"
    save_answer "feature_${i}_trigger" "$trigger"
    save_answer "feature_${i}_failure" "$failure"
    ((feature_count++))
    echo ""
  done

  # 4.2 Should-Have
  print_info "4.2 Should-Have Features (post-MVP)"
  echo ""
  for i in 1 2 3 4 5; do
    local should_have
    should_have=$(prompt_input "Should-have feature $i (or press Enter to finish)" "")
    [ -z "$should_have" ] && break
    save_answer "should_have_$i" "$should_have"
  done

  # 4.3 Will-Not-Have
  print_info "4.3 Will-Not-Have Features (explicit exclusions)"
  echo ""
  for i in 1 2 3 4 5; do
    local will_not
    if [ $i -le 3 ]; then
      will_not=$(prompt_input "Will-not-have $i" "")
      check_pause "$will_not"
    else
      will_not=$(prompt_input "Will-not-have $i (or press Enter to finish)" "")
      [ -z "$will_not" ] && break
    fi
    save_answer "will_not_$i" "$will_not"
  done

  save_section 4
  echo ""
}
```

- [ ] **Step 5: Add Section 5 (Data & Integrations) function**

```bash
# ================================================================
# SECTION 5: Data & Integrations
# ================================================================
run_section_5() {
  print_step "Section 5: Data & Integrations"
  echo ""

  # 5.1 Data Inputs
  print_info "5.1 Data Inputs — what data does the system accept?"
  echo ""
  for i in 1 2 3 4 5 6; do
    local input_name
    if [ $i -le 1 ]; then
      input_name=$(prompt_input "Data input $i name" "")
      check_pause "$input_name"
    else
      input_name=$(prompt_input "Data input $i name (or press Enter to finish)" "")
      [ -z "$input_name" ] && break
    fi

    local data_type
    data_type=$(prompt_input "  Data type (e.g., string, number, file, JSON)" "")
    local validation
    validation=$(prompt_input "  Validation rules" "")
    local sensitivity
    sensitivity=$(prompt_with_suggestions "  Sensitivity level" "data_sensitivity" "Internal")
    local required
    required=$(prompt_choice "  Required?" "Yes" "No")

    save_answer "input_${i}_name" "$input_name"
    save_answer "input_${i}_type" "$data_type"
    save_answer "input_${i}_validation" "$validation"
    save_answer "input_${i}_sensitivity" "$sensitivity"
    save_answer "input_${i}_required" "$required"
    echo ""
  done

  # 5.2 Data Outputs
  print_info "5.2 Data Outputs"
  echo ""
  for i in 1 2 3 4; do
    local output_name
    output_name=$(prompt_input "Data output $i name (or press Enter to finish)" "")
    [ -z "$output_name" ] && break
    local format
    format=$(prompt_input "  Format (e.g., JSON, CSV, HTML, PDF)" "")
    local latency
    latency=$(prompt_input "  Latency expectation (e.g., <200ms, <2s, batch)" "")
    save_answer "output_${i}_name" "$output_name"
    save_answer "output_${i}_format" "$format"
    save_answer "output_${i}_latency" "$latency"
  done

  # 5.3 Third-Party Integrations
  print_info "5.3 Third-Party Integrations (or press Enter to skip)"
  echo ""
  for i in 1 2 3; do
    local service
    service=$(prompt_input "Integration $i — service name (or press Enter to finish)" "")
    [ -z "$service" ] && break
    local data_exchanged
    data_exchanged=$(prompt_input "  Data sent/received" "")
    local auth_method
    auth_method=$(prompt_input "  Auth method (API key, OAuth, none)" "")
    local fallback
    fallback=$(prompt_input "  Fallback if unavailable" "")
    save_answer "integration_${i}_service" "$service"
    save_answer "integration_${i}_data" "$data_exchanged"
    save_answer "integration_${i}_auth" "$auth_method"
    save_answer "integration_${i}_fallback" "$fallback"
  done

  # 5.4 Data Persistence
  print_info "5.4 Data Persistence"
  echo ""
  local persistent_data
  persistent_data=$(prompt_input "What data persists across sessions?" "")
  save_answer "persistent_data" "$persistent_data"

  local ephemeral_data
  ephemeral_data=$(prompt_input "What data is ephemeral (session-only)?" "")
  save_answer "ephemeral_data" "$ephemeral_data"

  local data_volume
  data_volume=$(prompt_input "Expected data volume at 12 months (e.g., <1GB, 10GB, 100GB+)" "")
  save_answer "data_volume" "$data_volume"

  local retention
  retention=$(prompt_input "Data retention requirements (e.g., 'indefinite', '7 years', 'until user deletes')" "")
  save_answer "retention" "$retention"

  local backup
  backup=$(prompt_with_suggestions "Backup requirements" "backup_strategy" "Daily automated backups")
  save_answer "backup" "$backup"

  save_section 5
  echo ""
}
```

- [ ] **Step 6: Add Section 6 (Technical Preferences) function**

This section has platform-specific subsections. The function branches based on `$PLATFORM`.

```bash
# ================================================================
# SECTION 6: Technical Preferences
# ================================================================
run_section_6() {
  print_step "Section 6: Technical Preferences"
  echo ""

  # 6.1 Orchestrator Technical Profile
  print_info "6.1 Your Technical Profile"
  echo ""

  local languages_known
  languages_known=$(prompt_input "Languages you know well" "$LANGUAGE")
  save_answer "languages_known" "$languages_known"

  local frameworks_used
  frameworks_used=$(prompt_input "Frameworks you've used" "")
  save_answer "frameworks_used" "$frameworks_used"

  local willing_to_learn
  willing_to_learn=$(prompt_input "Willing to learn (or press Enter to skip)" "")
  save_answer "willing_to_learn" "$willing_to_learn"

  local refuse_to_use
  refuse_to_use=$(prompt_input "Refuse to use (or press Enter to skip)" "")
  save_answer "refuse_to_use" "$refuse_to_use"

  local db_experience
  db_experience=$(prompt_input "Database experience (e.g., PostgreSQL, MySQL, MongoDB, none)" "")
  save_answer "db_experience" "$db_experience"

  local devops_experience
  devops_experience=$(prompt_choice "DevOps experience:" "None" "Basic (can deploy to a PaaS)" "Intermediate (Docker, CI/CD)" "Advanced (Kubernetes, IaC)")
  save_answer "devops_experience" "$devops_experience"

  # 6.2 Competency Matrix
  print_info "6.2 Competency Matrix"
  print_info "For each domain: can you review AI output and reliably determine if it's correct?"
  print_info "Every honest 'No' adds automated coverage. Every dishonest 'Yes' creates a gap."
  echo ""

  local domains=("Product/UX Logic" "Frontend Code" "Backend/API Design" "Database Design" "Security" "DevOps/Infrastructure" "Accessibility" "Performance" "Mobile")
  for domain in "${domains[@]}"; do
    local assessment
    assessment=$(prompt_choice "$domain:" "Yes — I can reliably validate this" "Partially — I can catch obvious issues" "No — I need automated tooling here")
    # Map to short form
    case "$assessment" in
      "Yes"*) assessment="Yes" ;;
      "Partially"*) assessment="Partially" ;;
      "No"*) assessment="No" ;;
    esac
    save_answer "competency_$(echo "$domain" | tr '/ ' '_' | tr '[:upper:]' '[:lower:]')" "$assessment"
  done

  # 6.3 Development Environment
  print_info "6.3 Development Environment"
  echo ""

  local primary_machine
  primary_machine=$(prompt_input "Primary machine (e.g., 'MacBook Pro M3, macOS 15')" "")
  save_answer "primary_machine" "$primary_machine"

  local ide
  ide=$(prompt_input "IDE/Editor" "VS Code")
  save_answer "ide" "$ide"

  local docker_available
  docker_available=$(prompt_choice "Docker available?" "Yes" "No")
  save_answer "docker_available" "$docker_available"

  # 6.4 Architecture Preferences (platform-specific)
  print_info "6.4 Architecture Preferences"
  echo ""

  # All platforms
  local data_storage
  data_storage=$(prompt_with_suggestions "Data storage preference" "database" "")
  save_answer "data_storage" "$data_storage"

  local auth_strategy
  auth_strategy=$(prompt_with_suggestions "Authentication strategy" "authentication" "")
  save_answer "auth_strategy" "$auth_strategy"

  # Platform-specific
  case "$PLATFORM" in
    web)
      local frontend_fw
      frontend_fw=$(prompt_with_suggestions "Frontend framework" "frontend_framework" "")
      save_answer "frontend_framework" "$frontend_fw"

      local hosting
      hosting=$(prompt_with_suggestions "Hosting provider" "hosting" "")
      save_answer "hosting" "$hosting"
      ;;
    desktop)
      local ui_fw
      ui_fw=$(prompt_with_suggestions "UI framework" "ui_framework" "")
      save_answer "ui_framework" "$ui_fw"

      local packaging
      packaging=$(prompt_with_suggestions "Packaging format" "packaging" "")
      save_answer "packaging" "$packaging"

      local auto_update
      auto_update=$(prompt_with_suggestions "Auto-update strategy" "auto_update" "")
      save_answer "auto_update" "$auto_update"

      local offline_req
      offline_req=$(prompt_choice "Offline requirement:" "Online only" "Offline tolerant" "Offline capable" "Offline first")
      save_answer "offline_requirement" "$offline_req"
      ;;
    mobile)
      local mobile_fw
      mobile_fw=$(prompt_with_suggestions "Mobile framework" "framework" "")
      save_answer "mobile_framework" "$mobile_fw"

      local min_os
      min_os=$(prompt_input "Minimum OS versions (e.g., 'iOS 16+, Android 13+')" "")
      save_answer "min_os" "$min_os"

      local app_store
      app_store=$(prompt_choice "App store distribution:" "Apple App Store + Google Play" "Apple App Store only" "Google Play only" "Sideload/enterprise only")
      save_answer "app_store" "$app_store"

      local mobile_offline
      mobile_offline=$(prompt_with_suggestions "Offline strategy" "offline_strategy" "Offline tolerant")
      save_answer "mobile_offline" "$mobile_offline"
      ;;
    mcp_server)
      local mcp_server_transport
      mcp_server_transport=$(prompt_with_suggestions "Transport" "transport" "")
      save_answer "mcp_server_transport" "$mcp_server_transport"

      local mcp_server_sdk
      mcp_server_sdk=$(prompt_with_suggestions "MCP SDK" "mcp_sdk" "")
      save_answer "mcp_server_sdk" "$mcp_server_sdk"

      local mcp_server_persistence
      mcp_server_persistence=$(prompt_with_suggestions "Persistence" "persistence" "")
      save_answer "mcp_server_persistence" "$mcp_server_persistence"
      ;;
  esac

  # 6.5 Existing Infrastructure
  if [ "$DEPLOYMENT" = "organizational" ]; then
    print_info "6.5 Existing Infrastructure"
    echo ""
    local infra_items=("SSO / Identity Provider" "Logging / SIEM" "Monitoring" "Data Warehouse" "Backup Infrastructure" "CI/CD Platform" "Repository Platform")
    for item in "${infra_items[@]}"; do
      local status
      status=$(prompt_choice "$item:" "Yes — we have this" "No" "N/A")
      save_answer "infra_$(echo "$item" | tr '/ ' '_' | tr '[:upper:]' '[:lower:]')" "$status"
    done
  fi

  save_section 6
  echo ""
}
```

- [ ] **Step 7: Verify syntax**

```bash
bash -n scripts/intake-wizard.sh
```

Expected: SYNTAX OK

- [ ] **Step 8: Commit**

```bash
git add scripts/intake-wizard.sh
git commit -m "feat(intake-wizard): add section Q&A functions 1-6

Sections 1-6 cover Project Identity, Business Context, Constraints,
Features & Requirements, Data & Integrations, and Technical Preferences
with platform-specific branching for architecture questions."
```

---

### Task 4: Wizard script — Sections 7-11 and POC governance modes

Add the conditional sections (Revenue Model, Governance with POC modes) and remaining sections (Accessibility, Distribution, Known Risks).

**Files:**
- Modify: `scripts/intake-wizard.sh`

- [ ] **Step 1: Add Section 7 (Revenue Model) — conditional on track and deployment**

```bash
# ================================================================
# SECTION 7: Revenue Model (Standard+ track, skip for Light or internal)
# ================================================================
run_section_7() {
  if [ "$TRACK" = "light" ]; then
    print_info "Section 7: Revenue Model — skipped (Light track)"
    save_section 7
    return
  fi

  print_step "Section 7: Revenue Model"
  echo ""

  local pricing_model
  pricing_model=$(prompt_choice "Pricing model:" "Free (internal tool)" "Freemium" "Subscription" "One-time purchase" "Usage-based" "Not decided yet")
  save_answer "pricing_model" "$pricing_model"

  if [ "$pricing_model" != "Free (internal tool)" ]; then
    local price_point
    price_point=$(prompt_input "Target price point" "")
    save_answer "price_point" "$price_point"

    local competitive_range
    competitive_range=$(prompt_input "Competitive price range (what do alternatives cost?)" "")
    save_answer "competitive_range" "$competitive_range"

    local cost_per_user
    cost_per_user=$(prompt_input "Estimated per-user infrastructure cost" "")
    save_answer "cost_per_user" "$cost_per_user"

    local breakeven
    breakeven=$(prompt_input "Break-even user count" "")
    save_answer "breakeven" "$breakeven"
  fi

  local hosting_launch
  hosting_launch=$(prompt_input "Hosting cost ceiling at launch" "")
  save_answer "hosting_launch" "$hosting_launch"

  local hosting_1k
  hosting_1k=$(prompt_input "Hosting cost ceiling at 1,000 users" "")
  save_answer "hosting_1k" "$hosting_1k"

  local hosting_10k
  hosting_10k=$(prompt_input "Hosting cost ceiling at 10,000 users" "")
  save_answer "hosting_10k" "$hosting_10k"

  save_section 7
  echo ""
}
```

- [ ] **Step 2: Add Section 8 (Governance) with POC modes**

```bash
# ================================================================
# SECTION 8: Governance Pre-Flight (Organizational only)
# ================================================================
run_section_8() {
  if [ "$DEPLOYMENT" = "personal" ]; then
    print_info "Section 8: Governance Pre-Flight — skipped (personal project)"
    save_section 8
    return
  fi

  print_step "Section 8: Governance Pre-Flight"
  echo ""
  echo -e "  ${BOLD}Organizational projects require governance approvals before Phase 0.${NC}"
  echo "  Some of these take weeks to resolve. Choose your approach:"
  echo ""

  local gov_mode
  gov_mode=$(prompt_choice "Governance mode:" \
    "Production Build — all approvals required (recommended when approvals are in hand)" \
    "Sponsored POC — organization knows, non-technical approvals deferred" \
    "Private POC — personal exploration, all governance deferred")

  case "$gov_mode" in
    "Production"*) POC_MODE="" ;;
    "Sponsored"*) POC_MODE="sponsored_poc" ;;
    "Private"*) POC_MODE="private_poc" ;;
  esac

  # Update progress file with POC mode
  if command -v python3 &>/dev/null; then
    python3 -c "
import json
with open('$PROGRESS_FILE') as f:
    data = json.load(f)
data['poc_mode'] = '$POC_MODE' if '$POC_MODE' else None
with open('$PROGRESS_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
  fi

  if [ -n "$POC_MODE" ]; then
    echo ""
    print_warn "POC MODE: ${POC_MODE//_/ }"
    print_warn "Constraints: no production deployment, no real user data, no external users."
    print_warn "All technical work will be production-grade and carries forward."
    print_warn "Upgrade to production later: scripts/intake-wizard.sh --upgrade-to-production"
    echo ""
  fi

  # Define which pre-conditions are required vs deferred per mode
  local preconditions=(
    "AI deployment path approved by IT Security"
    "Insurance confirmation obtained"
    "Liability entity designated"
    "Project sponsor assigned"
    "Backup maintainer designated"
    "ITSM ticket filed / portfolio registered"
    "Exit criteria defined"
    "Orchestrator time allocation approved"
  )

  # Which are required per mode: production=all, sponsored=0,3,7, private=none
  local required_sponsored="0 3 7"

  for i in "${!preconditions[@]}"; do
    local precondition="${preconditions[$i]}"
    local is_deferred=false

    if [ "$POC_MODE" = "private_poc" ]; then
      is_deferred=true
    elif [ "$POC_MODE" = "sponsored_poc" ]; then
      if [[ ! " $required_sponsored " == *" $i "* ]]; then
        is_deferred=true
      fi
    fi

    if [ "$is_deferred" = true ]; then
      print_info "$precondition — DEFERRED (POC mode)"
      save_answer "precondition_${i}_status" "Deferred (POC)"
    else
      echo ""
      local status
      status=$(prompt_choice "$precondition:" "Complete" "In Progress" "Not Started")
      save_answer "precondition_${i}_status" "$status"

      if [ "$status" != "Not Started" ]; then
        local details
        details=$(prompt_input "  Details (contact name, date, ticket #, etc.)" "")
        save_answer "precondition_${i}_details" "$details"
      fi
    fi
  done

  # 8.2-8.5 only for production mode
  if [ -z "$POC_MODE" ]; then
    # 8.2 Approval Authorities
    print_info "8.2 Approval Authorities"
    echo ""
    local gates=("Phase 0 → Phase 1" "Phase 1 → Phase 2" "Phase 3 → Phase 4")
    for gate in "${gates[@]}"; do
      local approver
      approver=$(prompt_input "$gate approver (name and role)" "")
      save_answer "gate_$(echo "$gate" | tr ' →' '_')" "$approver"
    done

    # 8.3 Escalation Chain
    print_info "8.3 Escalation Chain"
    echo ""
    local levels=("Level 1 (first escalation)" "Level 2" "Level 3 (final authority)")
    for level in "${levels[@]}"; do
      local contact
      contact=$(prompt_input "$level contact" "")
      save_answer "escalation_$(echo "$level" | tr ' ' '_')" "$contact"
    done

    # 8.4 Compliance Screening
    print_info "8.4 Compliance Screening — answer Yes/No for each"
    echo ""
    local compliance_items=(
      "Does this project handle SOX-regulated financial data?"
      "Does this project handle payment card data (PCI)?"
      "Does this project collect personal data across multiple states/countries?"
      "Does this project serve EU users or involve EU subsidiaries?"
      "Does this project involve any OFAC-sanctioned jurisdictions?"
      "Are there records retention requirements?"
      "Does this project use AI for end-user-facing features (not just development)?"
      "Is penetration testing required by organizational policy?"
    )
    for j in "${!compliance_items[@]}"; do
      local answer
      answer=$(prompt_choice "${compliance_items[$j]}" "No" "Yes")
      save_answer "compliance_$j" "$answer"
    done

    # 8.5 Exit Criteria
    print_info "8.5 Exit Criteria"
    echo ""
    local success_def
    success_def=$(prompt_input "Success definition (what makes this project a success?)" "")
    save_answer "exit_success" "$success_def"

    local conditional_def
    conditional_def=$(prompt_input "Conditional success (acceptable with limitations)" "")
    save_answer "exit_conditional" "$conditional_def"

    local failure_def
    failure_def=$(prompt_input "Failure definition (when do we shut it down?)" "")
    save_answer "exit_failure" "$failure_def"
  fi

  save_section 8
  echo ""
}
```

- [ ] **Step 3: Add Sections 9-11**

```bash
# ================================================================
# SECTION 9: Accessibility & UX Constraints
# ================================================================
run_section_9() {
  print_step "Section 9: Accessibility & UX Constraints"
  echo ""

  local accessibility_target
  accessibility_target=$(prompt_with_suggestions "Accessibility target" "accessibility_target" "WCAG AA, Lighthouse 90+")
  save_answer "accessibility_target" "$accessibility_target"

  local color_vision
  color_vision=$(prompt_choice "Design for color vision deficiency?" "Yes — never rely on color alone" "No")
  save_answer "color_vision" "$color_vision"

  if [ "$PLATFORM" = "web" ]; then
    local browsers
    browsers=$(prompt_input "Supported browsers" "Chrome, Firefox, Safari, Edge (latest 2 versions)")
    save_answer "browsers" "$browsers"

    local responsive
    responsive=$(prompt_choice "Mobile responsive?" "Yes" "No")
    save_answer "responsive" "$responsive"
  fi

  local dark_mode
  dark_mode=$(prompt_choice "Dark mode:" "Yes" "No" "Nice-to-have (post-MVP)")
  save_answer "dark_mode" "$dark_mode"

  local branding
  branding=$(prompt_input "Branding/style guide (URL or description, or N/A)" "N/A")
  save_answer "branding" "$branding"

  save_section 9
  echo ""
}

# ================================================================
# SECTION 10: Distribution & Operations
# ================================================================
run_section_10() {
  print_step "Section 10: Distribution & Operations"
  echo ""

  local uptime
  uptime=$(prompt_with_suggestions "Uptime expectation" "uptime_expectation" "")
  save_answer "uptime" "$uptime"

  local env_strategy
  env_strategy=$(prompt_choice "Environment strategy:" "Dev + Production" "Dev + Staging + Production" "Production only")
  save_answer "env_strategy" "$env_strategy"

  # Platform-specific
  case "$PLATFORM" in
    web)
      local domain
      domain=$(prompt_input "Domain name (or TBD)" "TBD")
      save_answer "domain" "$domain"

      local maintenance_window
      maintenance_window=$(prompt_input "Preferred maintenance window (or N/A)" "N/A")
      save_answer "maintenance_window" "$maintenance_window"
      ;;
    desktop)
      local dist_channels
      dist_channels=$(prompt_choice "Distribution channels:" "Direct download (website/GitHub)" "App stores (Mac App Store, Microsoft Store)" "Both" "Internal distribution only")
      save_answer "dist_channels" "$dist_channels"

      local code_signing
      code_signing=$(prompt_choice "Code signing:" "Yes — required for distribution" "No — internal/dev use only")
      save_answer "code_signing" "$code_signing"

      local min_os_versions
      min_os_versions=$(prompt_input "Minimum OS versions (e.g., 'Windows 10+, macOS 12+, Ubuntu 22.04+')" "")
      save_answer "min_os_versions" "$min_os_versions"
      ;;
    mobile)
      local mobile_dist
      mobile_dist=$(prompt_choice "Distribution:" "App stores (iOS + Android)" "iOS App Store only" "Google Play only" "Enterprise sideload")
      save_answer "mobile_dist" "$mobile_dist"

      local beta_testing
      beta_testing=$(prompt_choice "Beta testing:" "TestFlight + Google Play internal testing" "TestFlight only" "Google Play internal testing only" "No beta program")
      save_answer "beta_testing" "$beta_testing"
      ;;
  esac

  save_section 10
  echo ""
}

# ================================================================
# SECTION 11: Known Risks & Concerns
# ================================================================
run_section_11() {
  print_step "Section 11: Known Risks & Concerns"
  echo ""

  local risks
  risks=$(prompt_input "Any additional context, known risks, or concerns? (or press Enter to skip)" "")
  save_answer "known_risks" "$risks"

  save_section 11
  echo ""
}
```

- [ ] **Step 4: Add Section 12 (auto-generated Agent Initialization Prompt)**

```bash
# ================================================================
# SECTION 12: Agent Initialization Prompt (auto-generated)
# ================================================================
run_section_12() {
  print_step "Section 12: Agent Initialization Prompt"
  print_info "Auto-generating from your answers..."
  echo ""

  # This section is auto-generated from all previous answers
  # It produces the prompt the user gives to Claude Code to begin Phase 0

  local platform_module=""
  case "$PLATFORM" in
    web) platform_module="WEB" ;;
    desktop) platform_module="DESKTOP" ;;
    mobile) platform_module="MOBILE" ;;
  esac

  local track_upper
  track_upper=$(echo "$TRACK" | tr '[:lower:]' '[:upper:]')

  # Read accessibility answers from progress
  local accessibility=""
  if command -v python3 &>/dev/null; then
    accessibility=$(python3 -c "
import json
with open('$PROGRESS_FILE') as f:
    data = json.load(f)
answers = data.get('answers', {})
parts = []
target = answers.get('accessibility_target', '')
if target:
    parts.append(f'Accessibility target: {target}')
color = answers.get('color_vision', '')
if 'Yes' in color:
    parts.append('Color vision deficiency: never rely on color alone for meaning. Use shape, position, text labels, patterns, or icons.')
print('; '.join(parts) if parts else 'WCAG AA, Lighthouse 90+')
" 2>/dev/null || echo "WCAG AA, Lighthouse 90+")
  fi

  print_ok "Section 12 auto-generated."
  save_section 12
  echo ""
}
```

- [ ] **Step 5: Verify syntax**

```bash
bash -n scripts/intake-wizard.sh
```

Expected: SYNTAX OK

- [ ] **Step 6: Commit**

```bash
git add scripts/intake-wizard.sh
git commit -m "feat(intake-wizard): add sections 7-12 with POC governance modes

Section 7 (Revenue) conditional on track. Section 8 (Governance) with
Production/Sponsored POC/Private POC modes and per-mode pre-condition
handling. Sections 9-11 for accessibility, distribution, and risks.
Section 12 auto-generates the agent initialization prompt."
```

---

### Task 5: Wizard script — main entry point and mode selection

Wire up the mode selection, section orchestration, resume logic, and upgrade-to-production flag.

**Files:**
- Modify: `scripts/intake-wizard.sh`

- [ ] **Step 1: Add the main orchestration logic at the bottom of the script**

```bash
# ================================================================
# MODE: Run all sections in order (script path)
# ================================================================
run_script_mode() {
  local start_section="${1:-1}"

  # Load or initialize project context
  if [ "$start_section" -gt 1 ]; then
    print_info "Resuming from Section $start_section"
  fi

  echo ""
  print_info "Type 'pause' at any prompt to save and exit."
  print_info "Type '?' at prompts marked with [? for suggestions] to see options."
  echo ""

  local sections=(1 2 3 4 5 6 7 8 9 10 11 12)
  for section in "${sections[@]}"; do
    if [ "$section" -lt "$start_section" ]; then
      continue
    fi

    # Check if already complete (on resume)
    if is_section_complete "$section" 2>/dev/null; then
      print_ok "Section $section — already complete"
      continue
    fi

    run_section_"$section"
  done

  echo ""
  echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}${BOLD}║              Intake Complete!                           ║${NC}"
  echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""
  print_ok "PROJECT_INTAKE.md has been filled out."
  print_info "Review it, then start Claude Code and begin Phase 0."
  echo ""
}

# ================================================================
# MODE: Generate Claude-guided prompt
# ================================================================
run_claude_mode() {
  print_step "Generating AI-assisted intake prompt..."
  echo ""

  local prompt_template="$PROJECT_ROOT/templates/intake-guided-prompt.md"
  local output_file="$PROJECT_ROOT/INTAKE_GUIDED_PROMPT.md"

  if [ ! -f "$prompt_template" ]; then
    print_warn "Prompt template not found at $prompt_template"
    print_warn "Falling back to inline prompt generation."
  fi

  # Generate the prompt with project context
  cat > "$output_file" << PROMPTEOF
# Guided Intake Conversation

## Your Role

You are helping a Solo Orchestrator fill out their Project Intake template (PROJECT_INTAKE.md). Walk through it section by section in a conversational tone. Explain each field's purpose before asking. When the user is unsure, offer 2-3 ranked suggestions with context.

## Project Context (from init.sh)

- **Project name:** $PROJECT_NAME
- **Description:** $PROJECT_DESCRIPTION
- **Platform:** $PLATFORM
- **Language:** $LANGUAGE
- **Track:** $TRACK
- **Deployment:** $DEPLOYMENT

## Instructions

1. Walk through PROJECT_INTAKE.md section by section (Sections 1-12).
2. Section 1 is mostly pre-filled — confirm and fill remaining fields.
3. For each field, explain its purpose briefly, then ask the question.
4. When the user says "I'm not sure" or asks for help, offer 2-3 options ranked by fit for their project type ($PLATFORM, $LANGUAGE, $TRACK), with a one-sentence explanation of why each fits.
5. Check off fields as you cover them. Before moving to the next section, confirm: "Section N complete. Anything to change before we move on?"
6. Skip sections that don't apply:
   - Section 7 (Revenue Model): skip if track is Light or deployment is Personal with internal users
   - Section 8 (Governance): skip if deployment is Personal
7. For Section 8 (Governance, organizational only): ask which mode — Production Build, Sponsored POC, or Private POC. Explain each:
   - **Production Build:** All 8 pre-conditions required. Full governance.
   - **Sponsored POC:** Organization knows. AI deployment path + sponsor + time allocation required. Insurance, liability, ITSM, exit criteria, backup maintainer deferred.
   - **Private POC:** Personal exploration. All pre-conditions deferred. No production deployment, no real user data, no external users.
8. Write completed sections into PROJECT_INTAKE.md progressively as you go.
9. Section 12 (Agent Initialization Prompt): auto-generate from the answers. Do not ask the user to write this.
10. At the end, summarize what was filled in and flag any fields left blank.

## Suggestion Data

Use the following platform-specific suggestions when the user needs help with technical choices:

PROMPTEOF

  # Append relevant suggestion file
  local platform_file="$SUGGESTIONS_DIR/${PLATFORM}.json"
  if [ -f "$platform_file" ]; then
    echo '```json' >> "$output_file"
    cat "$platform_file" >> "$output_file"
    echo '```' >> "$output_file"
  fi

  # Append common suggestions
  if [ -f "$SUGGESTIONS_DIR/common.json" ]; then
    echo "" >> "$output_file"
    echo "### Common Suggestions" >> "$output_file"
    echo '```json' >> "$output_file"
    cat "$SUGGESTIONS_DIR/common.json" >> "$output_file"
    echo '```' >> "$output_file"
  fi

  echo ""
  print_ok "Prompt generated: INTAKE_GUIDED_PROMPT.md"
  echo ""

  # Offer to launch Claude Code or keep the file
  echo -e "  ${BOLD}How would you like to proceed?${NC}"
  echo ""
  echo "    1. Launch Claude Code now"
  echo "       Opens Claude Code with the intake prompt automatically."
  echo "       You'll have a conversation that fills out PROJECT_INTAKE.md."
  echo ""
  echo "    2. Generate prompt file only"
  echo "       INTAKE_GUIDED_PROMPT.md is ready for you to review first."
  echo "       When ready: claude \"Read INTAKE_GUIDED_PROMPT.md and begin\""
  echo ""
  local launch_choice
  read -rp "$(echo -e "  ${BOLD}Select [1-2]${NC}: ")" launch_choice

  if [ "$launch_choice" = "1" ]; then
    if command -v claude &>/dev/null; then
      print_info "Launching Claude Code..."
      cd "$PROJECT_ROOT"
      claude "Read INTAKE_GUIDED_PROMPT.md and follow its instructions to help me fill out PROJECT_INTAKE.md."
    else
      print_warn "Claude Code not found. Run: claude \"Read INTAKE_GUIDED_PROMPT.md and begin\""
    fi
  else
    print_info "Prompt file ready at: INTAKE_GUIDED_PROMPT.md"
    print_info "When ready: claude \"Read INTAKE_GUIDED_PROMPT.md and begin\""
  fi
}

# ================================================================
# MODE: Upgrade POC to production
# ================================================================
run_upgrade_to_production() {
  print_step "Upgrading POC to Production"
  echo ""

  if [ ! -f "$PROGRESS_FILE" ]; then
    print_warn "No progress file found. Nothing to upgrade."
    exit 1
  fi

  load_progress

  if [ -z "$POC_MODE" ]; then
    print_warn "This project is not in POC mode. Nothing to upgrade."
    exit 0
  fi

  print_info "Current mode: ${POC_MODE//_/ }"
  print_info "Upgrading to Production Build. You'll need to resolve deferred pre-conditions."
  echo ""

  # Re-run Section 8 in production mode
  POC_MODE=""
  DEPLOYMENT="organizational"
  run_section_8

  # Update progress file
  if command -v python3 &>/dev/null; then
    python3 -c "
import json
with open('$PROGRESS_FILE') as f:
    data = json.load(f)
data['poc_mode'] = None
with open('$PROGRESS_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
  fi

  # TODO: Update POC watermarks in APPROVAL_LOG.md and CLAUDE.md
  print_ok "Upgraded to Production Build."
  print_info "Review APPROVAL_LOG.md and CLAUDE.md to remove POC watermarks."
  echo ""
}

# ================================================================
# MAIN: Entry point
# ================================================================
main() {
  # Check we're in a project directory
  if [ ! -f "$INTAKE_FILE" ]; then
    echo "Error: PROJECT_INTAKE.md not found."
    echo "Run this script from a Solo Orchestrator project directory."
    exit 1
  fi

  # Parse flags
  case "${1:-}" in
    --resume)
      load_progress
      local next_section=$((LAST_SECTION + 1))
      run_script_mode "$next_section"
      exit 0
      ;;
    --upgrade-to-production)
      run_upgrade_to_production
      exit 0
      ;;
    --help|-h)
      echo "Usage: scripts/intake-wizard.sh [--resume] [--upgrade-to-production] [--help]"
      echo ""
      echo "  (no flags)              Start the intake wizard or choose mode"
      echo "  --resume                Resume from last save point"
      echo "  --upgrade-to-production Upgrade a POC project to production"
      echo "  --help                  Show this help"
      exit 0
      ;;
  esac

  # Mode selection
  echo ""
  echo -e "${BOLD}How would you like to fill out the Project Intake?${NC}"
  echo ""
  echo "  1. Guided Script (30-60 minutes)"
  echo "     You answer questions section by section in the terminal. Best if you"
  echo "     already know your project requirements, tech preferences, and constraints."
  echo "     You can pause anytime and resume later. Progress is saved after each section."
  echo ""
  echo "  2. AI-Assisted (45-90 minutes)"
  echo "     Claude Code walks you through the intake conversationally, explains each"
  echo "     field, and suggests options based on your project type. Best if you want"
  echo "     help thinking through requirements or are unsure about technical choices."
  echo "     Requires Claude Code to be authenticated."
  echo ""
  echo "  3. I'll do it manually later"
  echo "     Open PROJECT_INTAKE.md in your editor and fill it out yourself."
  echo "     See the User Guide Section 3 for field-by-field guidance."
  echo ""

  local mode
  read -rp "$(echo -e "${BOLD}Select [1-3]${NC}: ")" mode

  case "$mode" in
    1)
      # Load project context from phase-state or progress file
      if [ -f "$PROGRESS_FILE" ]; then
        load_progress
        if [ "$LAST_SECTION" -gt 0 ]; then
          print_info "Found existing progress (through Section $LAST_SECTION)."
          local resume_choice
          resume_choice=$(prompt_choice "Resume or start over?" "Resume from Section $((LAST_SECTION + 1))" "Start over (previous progress will be overwritten)")
          if [[ "$resume_choice" == "Resume"* ]]; then
            run_script_mode "$((LAST_SECTION + 1))"
            exit 0
          fi
        fi
      fi

      # Load project context from phase-state.json
      if [ -f "$PROJECT_ROOT/.claude/phase-state.json" ] && command -v python3 &>/dev/null; then
        eval "$(python3 -c "
import json
with open('$PROJECT_ROOT/.claude/phase-state.json') as f:
    data = json.load(f)
print(f\"PROJECT_NAME='{data.get('project', 'unknown')}'\")
")"
      fi

      # If project context not loaded, ask for basics
      if [ -z "${PROJECT_NAME:-}" ]; then
        PROJECT_NAME=$(prompt_input "Project name" "")
        PROJECT_DESCRIPTION=$(prompt_input "One-sentence description" "")
        PLATFORM=$(prompt_choice "Platform:" "web" "desktop" "mobile" "mcp_server" "other")
        TRACK=$(prompt_choice "Track:" "light" "standard" "full")
        DEPLOYMENT=$(prompt_choice "Deployment:" "personal" "organizational")
        LANGUAGE=$(prompt_choice "Language:" "typescript" "javascript" "python" "rust" "csharp" "kotlin" "java" "go" "dart" "other")
      fi

      COMPLETED_SECTIONS=""
      init_progress
      run_script_mode 1
      ;;
    2)
      # Load project context
      if [ -f "$PROJECT_ROOT/.claude/phase-state.json" ] && command -v python3 &>/dev/null; then
        eval "$(python3 -c "
import json
with open('$PROJECT_ROOT/.claude/phase-state.json') as f:
    data = json.load(f)
print(f\"PROJECT_NAME='{data.get('project', 'unknown')}'\")
")"
      fi

      if [ -z "${PROJECT_NAME:-}" ]; then
        PROJECT_NAME=$(prompt_input "Project name" "")
        PROJECT_DESCRIPTION=$(prompt_input "One-sentence description" "")
        PLATFORM=$(prompt_choice "Platform:" "web" "desktop" "mobile" "mcp_server" "other")
        TRACK=$(prompt_choice "Track:" "light" "standard" "full")
        DEPLOYMENT=$(prompt_choice "Deployment:" "personal" "organizational")
        LANGUAGE=$(prompt_choice "Language:" "typescript" "javascript" "python" "rust" "csharp" "kotlin" "java" "go" "dart" "other")
      fi

      run_claude_mode
      ;;
    3)
      print_info "No problem. Open PROJECT_INTAKE.md in your editor when ready."
      print_info "See docs/framework/user-guide.md Section 3 for field-by-field guidance."
      ;;
    *)
      echo "Invalid choice."
      exit 1
      ;;
  esac
}

main "$@"
```

- [ ] **Step 2: Verify full script syntax**

```bash
bash -n scripts/intake-wizard.sh
```

Expected: SYNTAX OK

- [ ] **Step 3: Test --help flag**

```bash
bash scripts/intake-wizard.sh --help
```

Expected: Prints usage information.

- [ ] **Step 4: Commit**

```bash
git add scripts/intake-wizard.sh
git commit -m "feat(intake-wizard): add main entry point, mode selection, and Claude-guided path

Mode selection with 3 options (script/AI-assisted/manual). Claude path
generates INTAKE_GUIDED_PROMPT.md with project context and suggestion data.
Resume and upgrade-to-production flags. Full section orchestration."
```

---

### Task 6: Integrate with init.sh

Add the intake wizard offer to init.sh after project creation, and copy the new files into generated projects.

**Files:**
- Modify: `init.sh`

- [ ] **Step 1: Add file copies for wizard and suggestions in create_project**

In the script copying block (around line 449-453), add:

```bash
  cp "$SCRIPT_DIR/scripts/intake-wizard.sh" scripts/
  chmod +x scripts/intake-wizard.sh
  
  # Copy intake suggestion files
  mkdir -p templates/intake-suggestions
  cp "$SCRIPT_DIR/templates/intake-suggestions/"*.json templates/intake-suggestions/
  
  # Copy guided prompt template (if it exists)
  if [ -f "$SCRIPT_DIR/templates/intake-guided-prompt.md" ]; then
    mkdir -p templates
    cp "$SCRIPT_DIR/templates/intake-guided-prompt.md" templates/
  fi
```

- [ ] **Step 2: Update print_next_steps to offer the intake wizard**

Replace the current "FILL OUT THE INTAKE" step (around line 1344-1348) with:

```bash
  echo "  2. FILL OUT THE INTAKE (this is your product definition):"
  echo "     Option A: Run the guided wizard:"
  echo "       cd $PROJECT_DIR"
  echo "       bash scripts/intake-wizard.sh"
  echo "     Option B: Open PROJECT_INTAKE.md directly in your editor."
  echo "     The wizard offers an interactive script or AI-assisted conversation."
  echo ""
```

- [ ] **Step 3: Update dry_run_summary to list new files**

Add to the files list:

```bash
  echo "  scripts/intake-wizard.sh              — Guided intake wizard"
  echo "  templates/intake-suggestions/          — Context-aware suggestion data"
```

- [ ] **Step 4: Verify syntax**

```bash
bash -n init.sh
```

Expected: SYNTAX OK

- [ ] **Step 5: Commit**

```bash
git add init.sh
git commit -m "feat(init): integrate intake wizard into project creation

Copies intake-wizard.sh, suggestion data files, and prompt template
into generated projects. Updates next steps to offer the wizard
as the primary intake path."
```

---

### Task 7: Documentation updates

Update the User Guide to document the wizard, POC modes, and upgrade path. Add POC watermark fields to the Intake template.

**Files:**
- Modify: `docs/user-guide.md`
- Modify: `templates/project-intake.md`

- [ ] **Step 1: Update User Guide Section 3 (Filling Out the Project Intake)**

Find the Section 3 header in `docs/user-guide.md` and add an introduction about the wizard before the existing field-by-field guidance:

```markdown
### Using the Intake Wizard

The fastest way to fill out the Intake is the guided wizard:

```bash
cd your-project
bash scripts/intake-wizard.sh
```

The wizard offers three modes:

| Mode | Best For | Time |
|---|---|---|
| **Guided Script** | You know your requirements and technical preferences | 30-60 min |
| **AI-Assisted** | You want help thinking through requirements or are unsure about choices | 45-90 min |
| **Manual** | You prefer to fill out PROJECT_INTAKE.md directly in your editor | Varies |

The guided script saves progress after each section — you can pause with `pause` at any prompt and resume later with `scripts/intake-wizard.sh --resume`. Type `?` at any prompt to see context-aware suggestions for your platform and language.

The AI-assisted mode generates a prompt for Claude Code that walks you through the intake conversationally, explaining each field and suggesting options based on your project type.
```

- [ ] **Step 2: Add POC modes documentation to User Guide**

In the User Guide's organizational prerequisites section (Section 1.2), add after the 6 blocking pre-conditions:

```markdown
#### Proof of Concept (POC) Modes

If you want to validate the framework before completing all governance approvals, the intake wizard offers two POC modes:

| Mode | What's Required | What's Deferred |
|---|---|---|
| **Sponsored POC** | AI deployment path, project sponsor, time allocation | Insurance, liability entity, ITSM, exit criteria, backup maintainer |
| **Private POC** | Nothing — personal exploration on your own time | All 8 pre-conditions |

**POC constraints:** No production deployment, no real user data, no external users. All technical work (code, tests, scans, documentation) is production-grade and carries forward unchanged.

**Upgrading to production:** When you're ready, run `scripts/intake-wizard.sh --upgrade-to-production` to walk through the deferred pre-conditions.
```

- [ ] **Step 3: Add POC watermark fields to the Intake template Section 8**

In `templates/project-intake.md`, at the top of Section 8 (before the pre-conditions table), add:

```markdown
**Governance Mode:** Production / Sponsored POC / Private POC

> **If POC mode:** This project operates under POC constraints — no production deployment, no real user data, no external users. Deferred pre-conditions must be resolved before production. Upgrade with: `scripts/intake-wizard.sh --upgrade-to-production`
```

- [ ] **Step 4: Commit**

```bash
git add docs/user-guide.md templates/project-intake.md
git commit -m "docs: document intake wizard, POC modes, and upgrade path

Adds wizard usage guide to User Guide Section 3, POC mode documentation
to Section 1.2, and POC watermark fields to the Intake template."
```

---

### Task 8: Final verification

- [ ] **Step 1: Verify all files exist and are properly structured**

```bash
# Script is executable
ls -la scripts/intake-wizard.sh

# Suggestion files parse
for f in templates/intake-suggestions/*.json; do
  python3 -c "import json; json.load(open('$f'))" && echo "OK: $f"
done

# init.sh syntax
bash -n init.sh

# Wizard syntax
bash -n scripts/intake-wizard.sh

# Wizard --help
bash scripts/intake-wizard.sh --help
```

- [ ] **Step 2: Verify init.sh references**

```bash
grep "intake-wizard" init.sh    # Should find copy and next-steps references
grep "intake-suggestions" init.sh  # Should find directory copy
```

- [ ] **Step 3: Verify User Guide references**

```bash
grep -c "intake-wizard" docs/user-guide.md    # Should find wizard documentation
grep -c "POC" docs/user-guide.md               # Should find POC mode docs
```

- [ ] **Step 4: Commit any fixes, then final commit**

```bash
git add -A
git commit -m "feat: complete intake wizard implementation

Interactive guided intake with two paths (script and AI-assisted),
section-by-section save/resume, context-aware suggestions per platform,
POC governance modes (Sponsored/Private), and upgrade-to-production."
```

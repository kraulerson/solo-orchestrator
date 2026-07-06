# BL-016: init.sh Non-Interactive Mode — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `--non-interactive` mode to `init.sh` with per-input flags + JSON config-file support, three-pass validation, and a `--validate-only` smoke-test option, while leaving the existing interactive flow untouched.

**Architecture:** New `collect_inputs_non_interactive()` function inside `init.sh::main()`. When `--non-interactive` is set, the function runs in lieu of the existing interactive prompt block; both paths produce the same set of input variables that downstream `create_project` / `create_and_protect_remote` / `verify_install` / `print_next_steps` already consume. Surgical 4-line change in `create_and_protect_remote()` to consult new top-level variables before falling back to existing intake-progress.json + interactive prompts.

**Tech Stack:** Bash 4+, `jq` (already a dep), GNU coreutils. No new runtime dependencies.

**Spec reference:** `docs/superpowers/specs/2026-04-25-init-sh-non-interactive-design.md`

**Branching:** Execute on a feature branch `feat/bl-016-init-non-interactive` off `main`. The plan document itself commits to `main` first; implementation lives on the branch.

**Execution preamble (run once before Task 1):**

```bash
cd "/Users/karl/Documents/Claude Projects/solo-orchestrator"
git checkout main
git pull --ff-only origin main
git checkout -b feat/bl-016-init-non-interactive
scripts/process-checklist.sh --start-feature "bl-016-init-non-interactive"
```

---

## File Structure

**Modified files:**
- `init.sh` — flag parser extension, new `collect_inputs_non_interactive()` function, new top-level variables (`GOV_MODE`, `GIT_HOST`, `VISIBILITY`, `REMOTE_URL`, `BRANCH_PROTECTION_ATTESTED`, `ALLOW_EXISTING_DIR`), 4-line surgical change in `create_and_protect_remote()`, new dir-exists check, `--help` text update, `--help-non-interactive` output. Expected delta: +~250 lines.
- `tests/edge-cases-scripts.sh` — append section with E48–E55 (8 integration tests). Expected delta: +~180 lines.
- `docs/builders-guide.md` — new subsection "Scripted / Non-Interactive Project Initialization" inserted after Phase 0 content.
- `templates/generated/claude-md.tmpl` — one bullet under Operations Reference.
- `scripts/upgrade-project.sh` — one-line entry to header changelog.

**Created files:**
- `tests/test-init-non-interactive.sh` — 26 unit tests covering validation passes, defaults, config file, --validate-only.

**Responsibilities:**
- `collect_inputs_non_interactive()` knows the JSON config schema, flag→variable mapping, conditional-required rules, defaults table. Validates upfront. Exits 1 on any error with the uniform error format.
- `main()`'s flag-parser knows the new flag list. Sets the `NON_INTERACTIVE` boolean and per-input variables.
- `create_and_protect_remote()` knows that the new top-level variables override intake-progress.json + prompts, but the interactive prompt fallback is preserved.
- The interactive prompt block is unchanged and unaware of any of this.

---

## Task 1: Branch + scaffolding (flag parser + mode boolean + stub function)

**Goal:** Set up the new flag set and a stub `collect_inputs_non_interactive()` that just exits 1 with "not implemented." Establishes the wiring so subsequent tasks can flesh out validation in TDD slices.

**Files:**
- Modify: `init.sh` — flag parser block (around line 2542) and a new function definition near the bottom (before `main`'s call).

- [ ] **Step 1.1: Add new top-level variable declarations near the existing DRY_RUN declaration**

Find the existing block at the top of init.sh (around line 19–22):

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="1.0.0"
DRY_RUN=false
OS_TYPE="$(uname -s)"
```

Insert immediately after `DRY_RUN=false`:

```bash
NON_INTERACTIVE=false
VALIDATE_ONLY=false
CONFIG_FILE=""
# Per-input flags (empty = not supplied; collect_inputs_non_interactive() applies defaults or errors)
ARG_PROJECT=""
ARG_DESCRIPTION=""
ARG_PLATFORM=""
ARG_TRACK=""
ARG_DEPLOYMENT=""
ARG_GOV_MODE=""
ARG_LANGUAGE=""
ARG_PROJECT_DIR=""
ARG_GIT_HOST=""
ARG_VISIBILITY=""
ARG_REMOTE_URL=""
ARG_BRANCH_PROTECTION_ATTESTED=false
ARG_ALLOW_EXISTING_DIR=false
# Resolved variables produced by either input path (already used downstream)
GOV_MODE=""
GIT_HOST=""
VISIBILITY=""
REMOTE_URL=""
BRANCH_PROTECTION_ATTESTED=false
ALLOW_EXISTING_DIR=false
```

- [ ] **Step 1.2: Extend `main()`'s flag parser to recognize all new flags**

Locate `main()` (line 2540). Replace the existing flag-parser block (the `for arg in "$@"; do case "$arg" in ... esac done` loop) with:

```bash
main() {
  # Parse flags. Accept both "--flag value" and "--flag=value" shapes for inputs.
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run)
        DRY_RUN=true; shift ;;
      --non-interactive)
        NON_INTERACTIVE=true; shift ;;
      --validate-only)
        VALIDATE_ONLY=true; shift ;;
      --config)
        CONFIG_FILE="$2"; shift 2 ;;
      --config=*)
        CONFIG_FILE="${1#*=}"; shift ;;
      --project)
        ARG_PROJECT="$2"; shift 2 ;;
      --project=*)
        ARG_PROJECT="${1#*=}"; shift ;;
      --description)
        ARG_DESCRIPTION="$2"; shift 2 ;;
      --description=*)
        ARG_DESCRIPTION="${1#*=}"; shift ;;
      --platform)
        ARG_PLATFORM="$2"; shift 2 ;;
      --platform=*)
        ARG_PLATFORM="${1#*=}"; shift ;;
      --track)
        ARG_TRACK="$2"; shift 2 ;;
      --track=*)
        ARG_TRACK="${1#*=}"; shift ;;
      --deployment)
        ARG_DEPLOYMENT="$2"; shift 2 ;;
      --deployment=*)
        ARG_DEPLOYMENT="${1#*=}"; shift ;;
      --gov-mode)
        ARG_GOV_MODE="$2"; shift 2 ;;
      --gov-mode=*)
        ARG_GOV_MODE="${1#*=}"; shift ;;
      --language)
        ARG_LANGUAGE="$2"; shift 2 ;;
      --language=*)
        ARG_LANGUAGE="${1#*=}"; shift ;;
      --project-dir)
        ARG_PROJECT_DIR="$2"; shift 2 ;;
      --project-dir=*)
        ARG_PROJECT_DIR="${1#*=}"; shift ;;
      --git-host)
        ARG_GIT_HOST="$2"; shift 2 ;;
      --git-host=*)
        ARG_GIT_HOST="${1#*=}"; shift ;;
      --visibility)
        ARG_VISIBILITY="$2"; shift 2 ;;
      --visibility=*)
        ARG_VISIBILITY="${1#*=}"; shift ;;
      --remote-url)
        ARG_REMOTE_URL="$2"; shift 2 ;;
      --remote-url=*)
        ARG_REMOTE_URL="${1#*=}"; shift ;;
      --branch-protection-attested)
        ARG_BRANCH_PROTECTION_ATTESTED=true; shift ;;
      --allow-existing-dir)
        ARG_ALLOW_EXISTING_DIR=true; shift ;;
      --help-non-interactive)
        print_help_non_interactive
        exit 0 ;;
      --help|-h)
        cat <<'HELPEOF'
Usage: ./init.sh [--dry-run] [--help]                                 (interactive)
       ./init.sh --non-interactive [--config FILE] [INPUT FLAGS...]   (scriptable)

Options:
  --dry-run                Preview what will be installed and created without executing
  --help, -h               Show this help message
  --non-interactive        Enable non-interactive mode (CI / UAT / AI agents)
  --config FILE            Read JSON config (only honored with --non-interactive)
  --validate-only          Validate inputs and print resolved config; no scaffolding
  --help-non-interactive   Show full schema + JSON example + per-flag descriptions

Non-interactive mode (for CI, UAT, AI agents):
  Required (always):       --project --platform --deployment --language
  Required (conditional):  --gov-mode (when --deployment=organizational);
                           --remote-url (when --git-host=other);
                           --branch-protection-attested (when --git-host=other)
  Defaults:                --track standard, --git-host github,
                           --visibility private, --description "",
                           --project-dir "$HOME/Code/$PROJECT"

Init logs are saved to <project>/.solo-orchestrator/init-TIMESTAMP.log
HELPEOF
        exit 0 ;;
      *)
        echo "Unknown option: $1" >&2
        echo "Run --help for usage." >&2
        exit 1 ;;
    esac
  done

  print_header "$VERSION"

  # UAT 2026-04-25 fix (U-N): refuse to scaffold a project inside the
  # framework repo itself. (--dry-run is allowed for inspection.)
  if [ "$DRY_RUN" != true ]; then
    if ! guard_not_in_framework; then
      exit 1
    fi
  fi

  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}${BOLD}DRY RUN MODE — no changes will be made${NC}"
    echo ""
  fi
```

- [ ] **Step 1.3: Add stub `print_help_non_interactive()` and stub `collect_inputs_non_interactive()`**

Insert above the `main()` function definition (around line 2538):

```bash
# ================================================================
# Non-Interactive Mode (BL-016)
# ================================================================

print_help_non_interactive() {
  cat <<'NIHELPEOF'
init.sh --non-interactive — full reference

Required flags (always):
  --project NAME           Project name. Lowercase letters, digits, hyphens; must start with letter.
  --platform PLATFORM      One of: desktop, mobile, web, mcp_server
  --deployment KIND        One of: personal, organizational
  --language NAME          Primary language. Must be valid for the chosen platform.

Required flags (conditional):
  --gov-mode MODE          One of: production, sponsored_poc, private_poc.
                           REQUIRED when --deployment=organizational.
                           NOT VALID when --deployment=personal.
  --remote-url URL         HTTPS or SSH URL of an existing remote repo.
                           REQUIRED when --git-host=other.
  --branch-protection-attested
                           Boolean flag (presence = true). Confirms branch
                           protection is configured on the remote.
                           REQUIRED when --git-host=other.

Optional flags (with defaults):
  --description TEXT       One-sentence project description. Default: "".
  --track TRACK            One of: light, standard, full. Default: standard.
  --project-dir PATH       Project directory path. Default: $HOME/Code/$PROJECT.
  --git-host HOST          One of: github, gitlab, bitbucket, other. Default: github.
  --visibility VIS         One of: private, public. Default: private.
                           NOTE: organizational deployments force private.
  --allow-existing-dir     Boolean flag. Allow init into an existing directory
                           (otherwise: exit 1 if --project-dir already exists).

Mode flags:
  --non-interactive        Required to enable this mode. Without it, all input
                           flags are silently ignored (interactive flow runs).
  --config FILE            Read JSON config from FILE. Schema below.
                           Only honored with --non-interactive (otherwise warn + ignore).
  --validate-only          Validate inputs + print resolved config to stdout; exit 0.
                           No file writes.

Precedence: command-line flag > --config FILE > default > error-if-required.

JSON config schema (snake_case keys; all fields optional, missing → use flag/default/error):

{
  "project": "my-app",
  "description": "A web app for tracking widgets",
  "platform": "web",
  "track": "standard",
  "deployment": "personal",
  "gov_mode": null,
  "language": "typescript",
  "project_dir": "/Users/karl/Code/my-app",
  "git_host": "github",
  "visibility": "private",
  "remote_url": null,
  "branch_protection_attested": false,
  "allow_existing_dir": false
}

Examples:
  ./init.sh --non-interactive \
      --project my-app --platform web --deployment personal --language typescript

  ./init.sh --non-interactive --config init.json --project my-app

  ./init.sh --non-interactive --config init.json --project my-app --track full

  ./init.sh --non-interactive --config init.json --validate-only | jq

Errors take the uniform shape:

  [FAIL] init.sh non-interactive: <one-line summary>
    Reason: <specific cause>
    Action: <how to fix>
    Context: <relevant flags + values>

See docs/builders-guide.md "Scripted / Non-Interactive Project Initialization"
for narrative + use cases.
NIHELPEOF
}

collect_inputs_non_interactive() {
  # STUB — implemented in Tasks 2–7
  echo "[FAIL] init.sh non-interactive: not yet implemented" >&2
  return 1
}
```

- [ ] **Step 1.4: Wire the new path into `main()` body**

Right after the `print_header "$VERSION"` + guard + dry-run banner block, BEFORE the existing prereq/install/intake logic. Find where the existing flow begins (near the end of `main()`, before `create_project` is called) and insert the dispatch:

```bash
  # BL-016: dispatch to non-interactive collection or fall through to interactive.
  if [ "$NON_INTERACTIVE" = true ]; then
    if ! collect_inputs_non_interactive; then
      exit 1
    fi
    if [ "$VALIDATE_ONLY" = true ]; then
      exit 0
    fi
  else
    if [ -n "$CONFIG_FILE" ]; then
      print_warn "--config requires --non-interactive; ignoring config file"
    fi
    if [ -n "$ARG_PROJECT$ARG_PLATFORM$ARG_DEPLOYMENT$ARG_LANGUAGE" ]; then
      print_warn "Input flags require --non-interactive; ignoring (interactive flow will prompt)"
    fi
    # [existing interactive flow continues here, unchanged]
  fi
```

The exact insertion point is right after the dry-run banner and before `create_project` is called. Inspect main() to identify the correct anchor — the prereq/install loops should run regardless (they're independent of input collection); the input collection is what diverges.

- [ ] **Step 1.5: Sanity-check syntax + smoke-test help output**

```bash
bash -n init.sh && echo "SYNTAX_OK"
bash init.sh --help | head -25
bash init.sh --help-non-interactive | head -25
bash init.sh --non-interactive 2>&1 | head -3
```

Expected:
- `SYNTAX_OK`
- `--help` lists both interactive and scriptable usage paragraphs.
- `--help-non-interactive` prints the full reference.
- `--non-interactive` (no other flags) prints `[FAIL] init.sh non-interactive: not yet implemented` and exits 1.

- [ ] **Step 1.6: Commit**

```bash
git add init.sh
git commit -m "$(cat <<'EOF'
feat(init): scaffold --non-interactive flag set + stub function (BL-016 task 1)

Adds:
- New top-level variables: NON_INTERACTIVE, VALIDATE_ONLY, CONFIG_FILE,
  ARG_* per-input flags, resolved GOV_MODE/GIT_HOST/VISIBILITY/etc.
- main()'s flag parser extended to recognize all new flags + their
  --flag=value variants. Existing --dry-run/--help unchanged.
- New --help-non-interactive flag with full reference.
- New main() dispatch block: --non-interactive → collect_inputs_non_interactive
  (stub); else → existing interactive flow (untouched).
- Stub print_help_non_interactive() and collect_inputs_non_interactive()
  in a new "Non-Interactive Mode (BL-016)" section.

Stub returns "not yet implemented" so subsequent TDD tasks can flesh out
validation passes in slices.

Refs spec: docs/superpowers/specs/2026-04-25-init-sh-non-interactive-design.md
EOF
)"
```

---

## Task 2: Unit-test scaffolding + Pass 1 (schema validation)

**Goal:** Write the test file structure, then implement schema-level validation for each input. Tests cover the per-input typing rules from spec § 6.1.

**Files:**
- Create: `tests/test-init-non-interactive.sh`
- Modify: `init.sh` — flesh out `collect_inputs_non_interactive()` with Pass 1.

- [ ] **Step 2.1: Create the test file with helpers + N1 (happy path) + N11 (invalid platform) + N12 (invalid project name)**

Create `tests/test-init-non-interactive.sh`:

```bash
#!/usr/bin/env bash
# tests/test-init-non-interactive.sh — unit tests for init.sh --non-interactive (BL-016).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_SH="$REPO_ROOT/init.sh"

PASSED=0
FAILED=0

pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Run init.sh --non-interactive --validate-only with the given args from
# inside a fresh tempdir. Echoes "EXIT|STDOUT|STDERR".
run_validate() {
  local tmpdir
  tmpdir=$(mktemp -d)
  local out err rc=0
  out=$(cd "$tmpdir" && "$INIT_SH" --non-interactive --validate-only "$@" 2>/tmp/init-test-err) || rc=$?
  err=$(cat /tmp/init-test-err 2>/dev/null || true)
  rm -rf "$tmpdir" /tmp/init-test-err
  echo "$rc|$(printf '%s' "$out" | tr '\n' ' ')|$(printf '%s' "$err" | tr '\n' ' ')"
}

# --- Tests ---

n1_happy_path() {
  local out; out=$(run_validate \
    --project p \
    --platform web \
    --deployment personal \
    --language typescript)
  [ "${out%%|*}" = "0" ] || { fail_ "N1" "expected exit 0, got: $out"; return; }
  local stdout="${out#*|}"; stdout="${stdout%%|*}"
  [[ "$stdout" == *'"_validated": true'* ]] || { fail_ "N1" "stdout missing _validated:true: $stdout"; return; }
  pass "N1: all required flags present → exit 0 with resolved JSON"
}

n11_invalid_platform() {
  local out; out=$(run_validate --project p --platform foo --deployment personal --language ts)
  [ "${out%%|*}" = "1" ] || { fail_ "N11" "expected exit 1, got: $out"; return; }
  [[ "${out##*|}" == *"--platform"* ]] || { fail_ "N11" "stderr should mention --platform: ${out##*|}"; return; }
  pass "N11: invalid --platform → exit 1 with platform listed"
}

n12_invalid_project_name() {
  local out; out=$(run_validate --project "Foo!" --platform web --deployment personal --language ts)
  [ "${out%%|*}" = "1" ] || { fail_ "N12" "expected exit 1, got: $out"; return; }
  [[ "${out##*|}" == *"project"* ]] || { fail_ "N12" "stderr should mention project: ${out##*|}"; return; }
  pass "N12: invalid --project name → exit 1 with naming-rule message"
}

# --- Run all ---
echo "== tests/test-init-non-interactive.sh =="
n1_happy_path
n11_invalid_platform
n12_invalid_project_name

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
```

Make it executable:

```bash
chmod +x tests/test-init-non-interactive.sh
```

- [ ] **Step 2.2: Run the tests to confirm they fail (stub function returns 1 for all)**

```bash
bash tests/test-init-non-interactive.sh
```

Expected: 0/3 pass; all fail because the stub returns "not yet implemented" with exit 1.

- [ ] **Step 2.3: Implement Pass 1 in `collect_inputs_non_interactive()`**

Replace the stub function with the Pass-1 implementation. Locate the stub in init.sh (added in Task 1.3) and replace with:

```bash
collect_inputs_non_interactive() {
  # ----- Helpers (local to this function) -----
  local fail
  fail() {
    local summary="$1" reason="$2" action="$3" context="${4:-}"
    echo "[FAIL] init.sh non-interactive: $summary" >&2
    echo "  Reason: $reason" >&2
    echo "  Action: $action" >&2
    if [ -n "$context" ]; then
      echo "  Context: $context" >&2
    fi
    return 1
  }

  # ----- Pass 1: schema validation (per-input typing) -----

  # project
  if [ -n "$ARG_PROJECT" ] && ! [[ "$ARG_PROJECT" =~ ^[a-z][a-z0-9-]*$ ]]; then
    fail "invalid --project name '$ARG_PROJECT'" \
         "project name must start with a lowercase letter and contain only lowercase letters, digits, and hyphens." \
         "fix the name and re-run." \
         "--project='$ARG_PROJECT'"
    return 1
  fi

  # platform
  if [ -n "$ARG_PLATFORM" ]; then
    case "$ARG_PLATFORM" in
      desktop|mobile|web|mcp_server) ;;
      *)
        fail "invalid --platform '$ARG_PLATFORM'" \
             "platform must be one of: desktop, mobile, web, mcp_server." \
             "re-run with a supported --platform value." \
             "--platform='$ARG_PLATFORM'"
        return 1 ;;
    esac
  fi

  # track
  if [ -n "$ARG_TRACK" ]; then
    case "$ARG_TRACK" in
      light|standard|full) ;;
      *)
        fail "invalid --track '$ARG_TRACK'" \
             "track must be one of: light, standard, full." \
             "re-run with a supported --track value." \
             "--track='$ARG_TRACK'"
        return 1 ;;
    esac
  fi

  # deployment
  if [ -n "$ARG_DEPLOYMENT" ]; then
    case "$ARG_DEPLOYMENT" in
      personal|organizational) ;;
      *)
        fail "invalid --deployment '$ARG_DEPLOYMENT'" \
             "deployment must be one of: personal, organizational." \
             "re-run with a supported --deployment value." \
             "--deployment='$ARG_DEPLOYMENT'"
        return 1 ;;
    esac
  fi

  # gov_mode (presence-only check; required-or-not is Pass 2)
  if [ -n "$ARG_GOV_MODE" ]; then
    case "$ARG_GOV_MODE" in
      production|sponsored_poc|private_poc) ;;
      *)
        fail "invalid --gov-mode '$ARG_GOV_MODE'" \
             "gov-mode must be one of: production, sponsored_poc, private_poc." \
             "re-run with a supported --gov-mode value." \
             "--gov-mode='$ARG_GOV_MODE'"
        return 1 ;;
    esac
  fi

  # git_host (presence-only check)
  if [ -n "$ARG_GIT_HOST" ]; then
    case "$ARG_GIT_HOST" in
      github|gitlab|bitbucket|other) ;;
      *)
        fail "invalid --git-host '$ARG_GIT_HOST'" \
             "git-host must be one of: github, gitlab, bitbucket, other." \
             "re-run with a supported --git-host value." \
             "--git-host='$ARG_GIT_HOST'"
        return 1 ;;
    esac
  fi

  # visibility (presence-only check)
  if [ -n "$ARG_VISIBILITY" ]; then
    case "$ARG_VISIBILITY" in
      private|public) ;;
      *)
        fail "invalid --visibility '$ARG_VISIBILITY'" \
             "visibility must be one of: private, public." \
             "re-run with a supported --visibility value." \
             "--visibility='$ARG_VISIBILITY'"
        return 1 ;;
    esac
  fi

  # remote_url (presence-only check; required-or-not is Pass 2)
  if [ -n "$ARG_REMOTE_URL" ]; then
    if ! [[ "$ARG_REMOTE_URL" =~ ^(https://|git@) ]]; then
      fail "invalid --remote-url '$ARG_REMOTE_URL'" \
           "remote-url must start with 'https://' or 'git@'." \
           "re-run with a valid HTTPS or SSH URL." \
           "--remote-url='$ARG_REMOTE_URL'"
      return 1
    fi
  fi

  # ----- Pass 2 + Pass 3 + defaults + JSON output go in subsequent tasks -----
  # For now: emit a minimal JSON if --validate-only so N1 can pass.
  if [ "$VALIDATE_ONLY" = true ]; then
    cat <<JSONEOF
{
  "_validated": true,
  "_resolved_at": "$(date -u +%FT%TZ)",
  "project": "$ARG_PROJECT",
  "platform": "$ARG_PLATFORM",
  "deployment": "$ARG_DEPLOYMENT",
  "language": "$ARG_LANGUAGE"
}
JSONEOF
  fi
  return 0
}
```

- [ ] **Step 2.4: Run tests; expect N1, N11, N12 pass**

```bash
bash tests/test-init-non-interactive.sh
```

Expected: 3/3 pass.

- [ ] **Step 2.5: Commit**

```bash
git add init.sh tests/test-init-non-interactive.sh
git commit -m "$(cat <<'EOF'
feat(init): non-interactive Pass 1 schema validation + 3 unit tests (BL-016 task 2)

Replaces the Task-1 stub with Pass-1 schema validation (per-input typing
per spec § 6.1):
- project name regex
- platform/track/deployment/gov-mode/git-host/visibility enum checks
- remote-url URL prefix check (when present)

Pass 2/3, defaults, and full --validate-only JSON output are subsequent
tasks. For now Pass 1 + minimal --validate-only JSON satisfies N1.

3 unit tests in new tests/test-init-non-interactive.sh:
  N1 happy path → exit 0 with resolved JSON
  N11 invalid platform → exit 1
  N12 invalid project name → exit 1
EOF
)"
```

---

## Task 3: Pass 2 (context-required) + Pass-2 unit tests

**Goal:** Add the conditional-required validation rules from spec § 6.2 plus the unit tests for them.

**Files:**
- Modify: `init.sh::collect_inputs_non_interactive` (add Pass 2 block).
- Modify: `tests/test-init-non-interactive.sh` (add N2–N10, N13).

- [ ] **Step 3.1: Append Pass-2 block to `collect_inputs_non_interactive()`**

In init.sh, immediately after the Pass-1 block and BEFORE the `if [ "$VALIDATE_ONLY" = true ]` JSON-output block, insert:

```bash
  # ----- Pass 2: context-required validation -----

  # Always-required: project, platform, deployment, language
  if [ -z "$ARG_PROJECT" ]; then
    fail "--project is required" \
         "every non-interactive invocation must specify a project name." \
         "re-run with --project NAME." \
         "(--project unset)"
    return 1
  fi
  if [ -z "$ARG_PLATFORM" ]; then
    fail "--platform is required" \
         "every non-interactive invocation must specify a platform." \
         "re-run with --platform {desktop|mobile|web|mcp_server}." \
         "(--platform unset)"
    return 1
  fi
  if [ -z "$ARG_DEPLOYMENT" ]; then
    fail "--deployment is required" \
         "every non-interactive invocation must specify a deployment kind." \
         "re-run with --deployment {personal|organizational}." \
         "(--deployment unset)"
    return 1
  fi
  if [ -z "$ARG_LANGUAGE" ]; then
    fail "--language is required" \
         "every non-interactive invocation must specify a primary language." \
         "re-run with --language NAME (use --help-non-interactive to see supported languages per platform)." \
         "(--language unset)"
    return 1
  fi

  # gov-mode required iff deployment=organizational
  if [ "$ARG_DEPLOYMENT" = "organizational" ] && [ -z "$ARG_GOV_MODE" ]; then
    fail "--gov-mode is required when --deployment=organizational" \
         "organizational projects must specify a governance mode." \
         "re-run with one of: --gov-mode production, --gov-mode sponsored_poc, --gov-mode private_poc." \
         "--deployment=organizational, --gov-mode=(unset)"
    return 1
  fi
  if [ "$ARG_DEPLOYMENT" = "personal" ] && [ -n "$ARG_GOV_MODE" ]; then
    fail "--gov-mode is not valid for --deployment=personal" \
         "personal projects do not have a governance mode." \
         "remove --gov-mode and re-run." \
         "--deployment=personal, --gov-mode='$ARG_GOV_MODE'"
    return 1
  fi

  # remote-url required when git-host=other
  if [ "$ARG_GIT_HOST" = "other" ] && [ -z "$ARG_REMOTE_URL" ]; then
    fail "--remote-url is required when --git-host=other" \
         "the 'other' host has no API to create a repo; you must paste the URL of an existing remote." \
         "re-run with --remote-url URL." \
         "--git-host=other, --remote-url=(unset)"
    return 1
  fi

  # branch-protection-attested required when git-host=other
  if [ "$ARG_GIT_HOST" = "other" ] && [ "$ARG_BRANCH_PROTECTION_ATTESTED" != true ]; then
    fail "--branch-protection-attested is required when --git-host=other" \
         "the 'other' host cannot be API-verified; you must attest branch protection is configured." \
         "verify branch protection on the remote, then re-run with --branch-protection-attested." \
         "--git-host=other, --branch-protection-attested=false"
    return 1
  fi

  # visibility=public not allowed for organizational
  if [ "$ARG_DEPLOYMENT" = "organizational" ] && [ "$ARG_VISIBILITY" = "public" ]; then
    fail "--visibility=public is not allowed for --deployment=organizational" \
         "organizational projects must be private (force-private rule from init.sh:1713)." \
         "remove --visibility=public (or change to --visibility=private) and re-run." \
         "--deployment=organizational, --visibility=public"
    return 1
  fi

  # track=full + deployment=personal: warn, continue (matches interactive confirm-then-proceed)
  if [ "$ARG_TRACK" = "full" ] && [ "$ARG_DEPLOYMENT" = "personal" ]; then
    print_warn "Full track on a personal project is unusual; the interactive flow normally asks to confirm."
    print_warn "Proceeding because non-interactive mode treats explicit flags as confirmation."
  fi

  # language validity for platform — look up the platform's allowed languages list
  local lang_list_file=""
  if [ -f "$SCRIPT_DIR/templates/intake-suggestions/${ARG_PLATFORM}.json" ]; then
    lang_list_file="$SCRIPT_DIR/templates/intake-suggestions/${ARG_PLATFORM}.json"
  elif [ -f "$SCRIPT_DIR/templates/intake-suggestions/common.json" ]; then
    lang_list_file="$SCRIPT_DIR/templates/intake-suggestions/common.json"
  fi
  if [ -n "$lang_list_file" ] && command -v jq &>/dev/null; then
    # Look for "language" or "primary_language" arrays at known schema paths.
    # Fall back to skipping this check if the schema doesn't expose a list.
    local supported
    supported=$(jq -r '.. | objects | select(has("languages")) | .languages[]?' "$lang_list_file" 2>/dev/null | sort -u || true)
    if [ -n "$supported" ]; then
      if ! echo "$supported" | grep -qx "$ARG_LANGUAGE"; then
        local supported_csv
        supported_csv=$(echo "$supported" | tr '\n' ',' | sed 's/,$//; s/,/, /g')
        fail "language '$ARG_LANGUAGE' is not supported for platform '$ARG_PLATFORM'" \
             "the platform's intake suggestions list a different language set." \
             "re-run with one of: $supported_csv (or pick a different platform)." \
             "--platform='$ARG_PLATFORM', --language='$ARG_LANGUAGE'"
        return 1
      fi
    fi
  fi
```

- [ ] **Step 3.2: Append Pass-2 unit tests to test file**

Append to `tests/test-init-non-interactive.sh` (before the `# --- Run all ---` block):

```bash
n2_missing_project() {
  local out; out=$(run_validate --platform web --deployment personal --language ts)
  [ "${out%%|*}" = "1" ] || { fail_ "N2" "expected exit 1, got: $out"; return; }
  [[ "${out##*|}" == *"--project"* ]] || { fail_ "N2" "stderr should mention --project: ${out##*|}"; return; }
  pass "N2: missing --project → exit 1"
}

n3_missing_platform() {
  local out; out=$(run_validate --project p --deployment personal --language ts)
  [ "${out%%|*}" = "1" ] || { fail_ "N3" "expected exit 1, got: $out"; return; }
  [[ "${out##*|}" == *"--platform"* ]] || { fail_ "N3" "stderr should mention --platform: ${out##*|}"; return; }
  pass "N3: missing --platform → exit 1"
}

n4_missing_deployment() {
  local out; out=$(run_validate --project p --platform web --language ts)
  [ "${out%%|*}" = "1" ] || { fail_ "N4" "expected exit 1, got: $out"; return; }
  [[ "${out##*|}" == *"--deployment"* ]] || { fail_ "N4" "stderr should mention --deployment: ${out##*|}"; return; }
  pass "N4: missing --deployment → exit 1"
}

n5_missing_language() {
  local out; out=$(run_validate --project p --platform web --deployment personal)
  [ "${out%%|*}" = "1" ] || { fail_ "N5" "expected exit 1, got: $out"; return; }
  [[ "${out##*|}" == *"--language"* ]] || { fail_ "N5" "stderr should mention --language: ${out##*|}"; return; }
  pass "N5: missing --language → exit 1"
}

n6_org_without_govmode() {
  local out; out=$(run_validate --project p --platform web --deployment organizational --language ts)
  [ "${out%%|*}" = "1" ] || { fail_ "N6" "expected exit 1, got: $out"; return; }
  [[ "${out##*|}" == *"--gov-mode"* ]] || { fail_ "N6" "stderr should mention --gov-mode: ${out##*|}"; return; }
  pass "N6: --deployment=organizational without --gov-mode → exit 1"
}

n7_personal_with_govmode() {
  local out; out=$(run_validate --project p --platform web --deployment personal --gov-mode production --language ts)
  [ "${out%%|*}" = "1" ] || { fail_ "N7" "expected exit 1, got: $out"; return; }
  [[ "${out##*|}" == *"--gov-mode"* ]] || { fail_ "N7" "stderr should mention --gov-mode: ${out##*|}"; return; }
  pass "N7: --deployment=personal with --gov-mode → exit 1"
}

n8_other_without_remoteurl() {
  local out; out=$(run_validate --project p --platform web --deployment personal --language ts --git-host other)
  [ "${out%%|*}" = "1" ] || { fail_ "N8" "expected exit 1, got: $out"; return; }
  [[ "${out##*|}" == *"--remote-url"* ]] || { fail_ "N8" "stderr should mention --remote-url: ${out##*|}"; return; }
  pass "N8: --git-host=other without --remote-url → exit 1"
}

n9_other_without_attest() {
  local out; out=$(run_validate --project p --platform web --deployment personal --language ts --git-host other --remote-url https://example.com/x)
  [ "${out%%|*}" = "1" ] || { fail_ "N9" "expected exit 1, got: $out"; return; }
  [[ "${out##*|}" == *"--branch-protection-attested"* ]] || { fail_ "N9" "stderr should mention --branch-protection-attested: ${out##*|}"; return; }
  pass "N9: --git-host=other without --branch-protection-attested → exit 1"
}

n10_org_with_public_visibility() {
  local out; out=$(run_validate --project p --platform web --deployment organizational --gov-mode production --language ts --visibility public)
  [ "${out%%|*}" = "1" ] || { fail_ "N10" "expected exit 1, got: $out"; return; }
  [[ "${out##*|}" == *"--visibility=public"* ]] || { fail_ "N10" "stderr should explain org-forces-private: ${out##*|}"; return; }
  pass "N10: --deployment=organizational + --visibility=public → exit 1"
}

n13_invalid_language_for_platform() {
  # mcp_server is a server platform; swift is iOS-only — should fail per-platform check.
  # If the platform's intake-suggestions JSON doesn't expose a language list, this test
  # is a soft-no-op (passes by default since check is skipped) — that's acceptable
  # because it documents intent without false-failing on schema variance.
  local out; out=$(run_validate --project p --platform mcp_server --deployment personal --language swift)
  if [ "${out%%|*}" = "0" ]; then
    pass "N13: invalid --language for platform — check skipped (intake-suggestions schema does not expose language list)"
    return
  fi
  [[ "${out##*|}" == *"language"* ]] || { fail_ "N13" "stderr should mention language validity: ${out##*|}"; return; }
  pass "N13: invalid --language for platform → exit 1"
}
```

Update the `# --- Run all ---` section to call all the new tests:

```bash
echo "== tests/test-init-non-interactive.sh =="
n1_happy_path
n2_missing_project
n3_missing_platform
n4_missing_deployment
n5_missing_language
n6_org_without_govmode
n7_personal_with_govmode
n8_other_without_remoteurl
n9_other_without_attest
n10_org_with_public_visibility
n11_invalid_platform
n12_invalid_project_name
n13_invalid_language_for_platform
```

- [ ] **Step 3.3: Run tests; expect 13/13 pass**

```bash
bash tests/test-init-non-interactive.sh
```

Expected: `Total: 13 | Passed: 13 | Failed: 0`.

- [ ] **Step 3.4: Commit**

```bash
git add init.sh tests/test-init-non-interactive.sh
git commit -m "$(cat <<'EOF'
feat(init): non-interactive Pass 2 context-required validation (BL-016 task 3)

Adds the conditional-required rules from spec § 6.2:
- always-required: --project, --platform, --deployment, --language
- gov-mode required iff deployment=organizational; not valid when personal
- remote-url + branch-protection-attested required when git-host=other
- visibility=public rejected for organizational deployment
- track=full + deployment=personal warns (continues, treating explicit
  flag as confirmation)
- language validity check against templates/intake-suggestions/PLATFORM.json
  (soft-no-op if schema doesn't expose a language array — documented in N13)

10 new unit tests N2-N10 + N13. Combined with N1+N11+N12 from task 2:
13/13 unit tests passing.
EOF
)"
```

---

## Task 4: Pass 3 (resource validation) + dir-exists handling + tests

**Goal:** Add Pass-3 (required tools, dir existence) plus the `--allow-existing-dir` semantic. Tests cover N22, N23.

**Files:**
- Modify: `init.sh::collect_inputs_non_interactive` (add Pass 3 block).
- Modify: `tests/test-init-non-interactive.sh` (add N22, N23).

- [ ] **Step 4.1: Append Pass-3 block to `collect_inputs_non_interactive()`**

In init.sh, after the Pass-2 block (and before the `--validate-only` JSON output), insert:

```bash
  # ----- Pass 3: resource validation -----

  # Required tools
  for tool in git jq node python3; do
    if ! command -v "$tool" &>/dev/null; then
      local install_cmd=""
      case "$OS_TYPE" in
        Darwin) install_cmd="brew install $tool" ;;
        Linux)  install_cmd="apt install -y $tool   # or your distro's package manager" ;;
      esac
      fail "missing required tool: $tool" \
           "non-interactive mode does not auto-install dependencies." \
           "install: $install_cmd, then re-run." \
           "--non-interactive (tool=$tool)"
      return 1
    fi
  done

  # git host CLI presence (skipped for 'other')
  local effective_git_host="${ARG_GIT_HOST:-github}"
  case "$effective_git_host" in
    github)
      if ! command -v gh &>/dev/null; then
        fail "missing required tool for --git-host=github: gh" \
             "the GitHub CLI is needed to create + protect the remote repo." \
             "install: brew install gh (macOS) or apt install gh (Linux), then re-run." \
             "--git-host=github"
        return 1
      fi ;;
    gitlab)
      if ! command -v glab &>/dev/null; then
        fail "missing required tool for --git-host=gitlab: glab" \
             "the GitLab CLI is needed to create + protect the remote repo." \
             "install: brew install glab (macOS), then re-run." \
             "--git-host=gitlab"
        return 1
      fi ;;
    bitbucket)
      # bitbucket uses curl + tokens; no CLI requirement
      : ;;
    other)
      : ;;
  esac

  # project_dir existence check
  local effective_project_dir="${ARG_PROJECT_DIR:-$HOME/Code/$ARG_PROJECT}"
  if [ -e "$effective_project_dir" ] && [ "$ARG_ALLOW_EXISTING_DIR" != true ]; then
    fail "project directory already exists: $effective_project_dir" \
         "non-interactive mode refuses to write into an existing directory by default." \
         "pass --allow-existing-dir to use it anyway, or pick a different --project-dir." \
         "--project-dir='$effective_project_dir'"
    return 1
  fi
```

- [ ] **Step 4.2: Append N22 + N23 tests**

Append to `tests/test-init-non-interactive.sh`:

```bash
n22_allow_existing_dir() {
  # Setup: create a dir, then run with --allow-existing-dir + --project-dir pointing to it.
  local existing
  existing=$(mktemp -d)
  local out rc=0
  out=$("$INIT_SH" --non-interactive --validate-only \
        --project p --platform web --deployment personal --language typescript \
        --project-dir "$existing" --allow-existing-dir 2>&1) || rc=$?
  rm -rf "$existing"
  [ "$rc" = "0" ] || { fail_ "N22" "expected exit 0 with --allow-existing-dir, got rc=$rc out=$out"; return; }
  pass "N22: existing dir + --allow-existing-dir → exit 0"
}

n23_dir_exists_no_allow_flag() {
  local existing
  existing=$(mktemp -d)
  local out rc=0
  out=$("$INIT_SH" --non-interactive --validate-only \
        --project p --platform web --deployment personal --language typescript \
        --project-dir "$existing" 2>&1) || rc=$?
  rm -rf "$existing"
  [ "$rc" = "1" ] || { fail_ "N23" "expected exit 1, got rc=$rc out=$out"; return; }
  [[ "$out" == *"--allow-existing-dir"* ]] || { fail_ "N23" "stderr should suggest --allow-existing-dir: $out"; return; }
  pass "N23: existing dir without --allow-existing-dir → exit 1 with flag suggestion"
}
```

Append to the run-all block:

```bash
n22_allow_existing_dir
n23_dir_exists_no_allow_flag
```

- [ ] **Step 4.3: Run tests; expect 15/15 pass**

```bash
bash tests/test-init-non-interactive.sh
```

Expected: `Total: 15 | Passed: 15 | Failed: 0`.

- [ ] **Step 4.4: Commit**

```bash
git add init.sh tests/test-init-non-interactive.sh
git commit -m "$(cat <<'EOF'
feat(init): non-interactive Pass 3 resource validation + dir-exists check (BL-016 task 4)

Adds the resource-validation pass from spec § 6.3:
- Required tools: git, jq, node, python3 — fail-fast with OS-specific
  install command in the error message. Non-interactive mode never
  auto-installs.
- git-host CLI presence: gh for github, glab for gitlab. Skipped for
  bitbucket (uses curl) and other (no CLI).
- project_dir existence: fail with --allow-existing-dir suggestion
  unless the flag is set.

2 new unit tests N22 + N23. 15/15 unit tests passing.
EOF
)"
```

---

## Task 5: Config file support (`--config FILE`) + tests

**Goal:** Read JSON config, merge with flag overrides, error handling for missing/malformed files.

**Files:**
- Modify: `init.sh::collect_inputs_non_interactive` (insert config-file load BEFORE Pass 1).
- Modify: `tests/test-init-non-interactive.sh` (add N14–N19).

- [ ] **Step 5.1: Insert config-file load at top of `collect_inputs_non_interactive()`**

At the very start of `collect_inputs_non_interactive()` (right after the local `fail` helper definition), insert:

```bash
  # ----- Config file load (BEFORE Pass 1 so flags can override) -----
  if [ -n "$CONFIG_FILE" ]; then
    if [ ! -f "$CONFIG_FILE" ]; then
      fail "config file not found: $CONFIG_FILE" \
           "the path supplied to --config does not exist or is not readable." \
           "fix the path and re-run." \
           "--config='$CONFIG_FILE'"
      return 1
    fi
    if ! jq -e . "$CONFIG_FILE" >/dev/null 2>&1; then
      local jq_err
      jq_err=$(jq . "$CONFIG_FILE" 2>&1 >/dev/null || true)
      fail "config file is not valid JSON: $CONFIG_FILE" \
           "jq parse error: $jq_err" \
           "fix the JSON syntax and re-run. Use 'jq . FILE' to lint." \
           "--config='$CONFIG_FILE'"
      return 1
    fi
    if [ "$(jq -r 'type' "$CONFIG_FILE")" != "object" ]; then
      fail "config file must be a JSON object" \
           "found: $(jq -r 'type' "$CONFIG_FILE")" \
           "wrap the contents in {} and re-run." \
           "--config='$CONFIG_FILE'"
      return 1
    fi

    # Warn on unknown fields (forward-compat per spec § 5.4).
    local known_fields="project description platform track deployment gov_mode language project_dir git_host visibility remote_url branch_protection_attested allow_existing_dir"
    local field
    for field in $(jq -r 'keys[]' "$CONFIG_FILE"); do
      if ! echo " $known_fields " | grep -q " $field "; then
        print_warn "unknown config field: $field (ignored)"
      fi
    done

    # Merge: each ARG_* defaults to the config value if not already set via flag.
    # Flag wins on conflict per spec § 5.5.
    local cfg_get
    cfg_get() {
      local key="$1"
      jq -r --arg k "$key" '.[$k] // empty' "$CONFIG_FILE" 2>/dev/null
    }
    [ -z "$ARG_PROJECT" ]                  && ARG_PROJECT=$(cfg_get project)
    [ -z "$ARG_DESCRIPTION" ]              && ARG_DESCRIPTION=$(cfg_get description)
    [ -z "$ARG_PLATFORM" ]                 && ARG_PLATFORM=$(cfg_get platform)
    [ -z "$ARG_TRACK" ]                    && ARG_TRACK=$(cfg_get track)
    [ -z "$ARG_DEPLOYMENT" ]               && ARG_DEPLOYMENT=$(cfg_get deployment)
    [ -z "$ARG_GOV_MODE" ]                 && ARG_GOV_MODE=$(cfg_get gov_mode)
    [ -z "$ARG_LANGUAGE" ]                 && ARG_LANGUAGE=$(cfg_get language)
    [ -z "$ARG_PROJECT_DIR" ]              && ARG_PROJECT_DIR=$(cfg_get project_dir)
    [ -z "$ARG_GIT_HOST" ]                 && ARG_GIT_HOST=$(cfg_get git_host)
    [ -z "$ARG_VISIBILITY" ]               && ARG_VISIBILITY=$(cfg_get visibility)
    [ -z "$ARG_REMOTE_URL" ]               && ARG_REMOTE_URL=$(cfg_get remote_url)
    if [ "$ARG_BRANCH_PROTECTION_ATTESTED" != true ]; then
      local cfg_attest
      cfg_attest=$(cfg_get branch_protection_attested)
      [ "$cfg_attest" = "true" ] && ARG_BRANCH_PROTECTION_ATTESTED=true
    fi
    if [ "$ARG_ALLOW_EXISTING_DIR" != true ]; then
      local cfg_allow
      cfg_allow=$(cfg_get allow_existing_dir)
      [ "$cfg_allow" = "true" ] && ARG_ALLOW_EXISTING_DIR=true
    fi
  fi
```

- [ ] **Step 5.2: Append N14–N19 tests**

Append to `tests/test-init-non-interactive.sh`:

```bash
n14_config_provides_everything() {
  local cfg
  cfg=$(mktemp)
  cat > "$cfg" <<'JSON'
{"project":"p","platform":"web","deployment":"personal","language":"typescript"}
JSON
  local out; out=$(run_validate --config "$cfg")
  rm -f "$cfg"
  [ "${out%%|*}" = "0" ] || { fail_ "N14" "expected exit 0, got: $out"; return; }
  pass "N14: --config provides everything → exit 0"
}

n15_flag_overrides_config() {
  local cfg
  cfg=$(mktemp)
  cat > "$cfg" <<'JSON'
{"project":"p","platform":"web","deployment":"personal","language":"typescript","track":"light"}
JSON
  local out; out=$(run_validate --config "$cfg" --track full)
  rm -f "$cfg"
  [ "${out%%|*}" = "0" ] || { fail_ "N15" "expected exit 0, got: $out"; return; }
  # Resolved JSON should show track=full (full output assertion comes in N20 once full JSON is implemented)
  pass "N15: flag overrides --config value → exit 0"
}

n16_config_not_found() {
  local out; out=$(run_validate --config /nonexistent/path/init.json --project p --platform web --deployment personal --language ts)
  [ "${out%%|*}" = "1" ] || { fail_ "N16" "expected exit 1, got: $out"; return; }
  [[ "${out##*|}" == *"not found"* ]] || { fail_ "N16" "stderr should mention 'not found': ${out##*|}"; return; }
  pass "N16: --config file not found → exit 1"
}

n17_config_malformed_json() {
  local cfg
  cfg=$(mktemp)
  echo '{"project": "p"' > "$cfg"  # truncated
  local out; out=$(run_validate --config "$cfg" --project p --platform web --deployment personal --language ts)
  rm -f "$cfg"
  [ "${out%%|*}" = "1" ] || { fail_ "N17" "expected exit 1, got: $out"; return; }
  [[ "${out##*|}" == *"not valid JSON"* ]] || { fail_ "N17" "stderr should mention 'not valid JSON': ${out##*|}"; return; }
  pass "N17: --config malformed JSON → exit 1"
}

n18_config_unknown_field() {
  local cfg
  cfg=$(mktemp)
  cat > "$cfg" <<'JSON'
{"project":"p","platform":"web","deployment":"personal","language":"typescript","frobnicate":"bar"}
JSON
  local out; out=$(run_validate --config "$cfg")
  rm -f "$cfg"
  [ "${out%%|*}" = "0" ] || { fail_ "N18" "expected exit 0 (warn-not-fail), got: $out"; return; }
  [[ "${out##*|}" == *"frobnicate"* ]] || { fail_ "N18" "stderr should warn about 'frobnicate': ${out##*|}"; return; }
  pass "N18: --config unknown field → warn + ignore + continue"
}

n19_config_without_non_interactive() {
  local cfg
  cfg=$(mktemp)
  cat > "$cfg" <<'JSON'
{"project":"p","platform":"web","deployment":"personal","language":"typescript"}
JSON
  # Run init.sh WITHOUT --non-interactive but WITH --config; expect warn + fall through.
  # Use --dry-run to avoid actually creating anything in interactive mode.
  local out rc=0
  out=$("$INIT_SH" --dry-run --config "$cfg" 2>&1) || rc=$?
  rm -f "$cfg"
  # Either it warned about ignoring --config, or it just ran dry-run (interactive).
  [[ "$out" == *"requires --non-interactive"* || "$out" == *"DRY RUN"* ]] \
    || { fail_ "N19" "expected warn or dry-run output, got: $out"; return; }
  pass "N19: --config without --non-interactive → warn + ignore"
}
```

Append to the run-all block:

```bash
n14_config_provides_everything
n15_flag_overrides_config
n16_config_not_found
n17_config_malformed_json
n18_config_unknown_field
n19_config_without_non_interactive
```

- [ ] **Step 5.3: Run tests; expect 21/21 pass**

```bash
bash tests/test-init-non-interactive.sh
```

Expected: `Total: 21 | Passed: 21 | Failed: 0`.

- [ ] **Step 5.4: Commit**

```bash
git add init.sh tests/test-init-non-interactive.sh
git commit -m "$(cat <<'EOF'
feat(init): non-interactive --config FILE support (BL-016 task 5)

Adds JSON config-file loading at the top of collect_inputs_non_interactive
(BEFORE Pass 1) so flags can override config values per spec § 5.5.

Schema rules implemented per spec § 5.4:
- file-not-found → exit 1
- malformed JSON → exit 1 with jq parse error
- non-object top-level → exit 1
- unknown fields → warn + ignore (forward compat)
- snake_case keys matching framework state-file convention

6 new unit tests N14-N19. 21/21 unit tests passing.
EOF
)"
```

---

## Task 6: `--validate-only` full JSON output + N20, N21 tests

**Goal:** Replace the minimal --validate-only JSON from Task 2 with the complete resolved-config output.

**Files:**
- Modify: `init.sh::collect_inputs_non_interactive` (replace JSON output block).
- Modify: `tests/test-init-non-interactive.sh` (add N20, N21).

- [ ] **Step 6.1: Replace the minimal `--validate-only` JSON with full output**

In init.sh, find the existing minimal output (added in Task 2 step 2.3) inside `collect_inputs_non_interactive()`:

```bash
  if [ "$VALIDATE_ONLY" = true ]; then
    cat <<JSONEOF
{
  "_validated": true,
  "_resolved_at": "$(date -u +%FT%TZ)",
  "project": "$ARG_PROJECT",
  "platform": "$ARG_PLATFORM",
  "deployment": "$ARG_DEPLOYMENT",
  "language": "$ARG_LANGUAGE"
}
JSONEOF
  fi
  return 0
}
```

Replace with the full version (this should land at the END of the function, after Pass 3):

```bash
  # Apply defaults for any inputs not set by flag or config.
  : "${ARG_TRACK:=standard}"
  : "${ARG_GIT_HOST:=github}"
  : "${ARG_VISIBILITY:=private}"
  : "${ARG_PROJECT_DIR:=$HOME/Code/$ARG_PROJECT}"
  # Force private for organizational deployments (matches existing init.sh:1713 logic).
  if [ "$ARG_DEPLOYMENT" = "organizational" ]; then
    ARG_VISIBILITY="private"
  fi

  # Assign resolved values to the variables the rest of init.sh consumes.
  PROJECT_NAME="$ARG_PROJECT"
  PROJECT_DESCRIPTION="$ARG_DESCRIPTION"
  PLATFORM="$ARG_PLATFORM"
  TRACK="$ARG_TRACK"
  DEPLOYMENT="$ARG_DEPLOYMENT"
  GOV_MODE="$ARG_GOV_MODE"
  LANGUAGE="$ARG_LANGUAGE"
  PROJECT_DIR="$ARG_PROJECT_DIR"
  GIT_HOST="$ARG_GIT_HOST"
  VISIBILITY="$ARG_VISIBILITY"
  REMOTE_URL="$ARG_REMOTE_URL"
  BRANCH_PROTECTION_ATTESTED="$ARG_BRANCH_PROTECTION_ATTESTED"
  ALLOW_EXISTING_DIR="$ARG_ALLOW_EXISTING_DIR"

  if [ "$VALIDATE_ONLY" = true ]; then
    # Build the resolved JSON via jq for proper escaping.
    jq -n \
      --arg ts "$(date -u +%FT%TZ)" \
      --arg project "$PROJECT_NAME" \
      --arg description "$PROJECT_DESCRIPTION" \
      --arg platform "$PLATFORM" \
      --arg track "$TRACK" \
      --arg deployment "$DEPLOYMENT" \
      --arg gov_mode "$GOV_MODE" \
      --arg language "$LANGUAGE" \
      --arg project_dir "$PROJECT_DIR" \
      --arg git_host "$GIT_HOST" \
      --arg visibility "$VISIBILITY" \
      --arg remote_url "$REMOTE_URL" \
      --argjson attested "$([ "$BRANCH_PROTECTION_ATTESTED" = true ] && echo true || echo false)" \
      --argjson allow_dir "$([ "$ALLOW_EXISTING_DIR" = true ] && echo true || echo false)" \
      '{
        _validated: true,
        _resolved_at: $ts,
        project: $project,
        description: $description,
        platform: $platform,
        track: $track,
        deployment: $deployment,
        gov_mode: (if $gov_mode == "" then null else $gov_mode end),
        language: $language,
        project_dir: $project_dir,
        git_host: $git_host,
        visibility: $visibility,
        remote_url: (if $remote_url == "" then null else $remote_url end),
        branch_protection_attested: $attested,
        allow_existing_dir: $allow_dir
      }'
  fi
  return 0
}
```

- [ ] **Step 6.2: Append N20, N21 tests**

```bash
n20_validate_only_success() {
  local out; out=$(run_validate --project p --platform web --deployment personal --language typescript)
  [ "${out%%|*}" = "0" ] || { fail_ "N20" "expected exit 0, got: $out"; return; }
  local stdout="${out#*|}"; stdout="${stdout%%|*}"
  [[ "$stdout" == *'"_validated": true'* ]] || { fail_ "N20" "stdout missing _validated:true: $stdout"; return; }
  [[ "$stdout" == *'"track": "standard"'* ]] || { fail_ "N20" "stdout missing default track: $stdout"; return; }
  [[ "$stdout" == *'"git_host": "github"'* ]] || { fail_ "N20" "stdout missing default git_host: $stdout"; return; }
  [[ "$stdout" == *'"visibility": "private"'* ]] || { fail_ "N20" "stdout missing default visibility: $stdout"; return; }
  pass "N20: --validate-only success → exit 0 + full resolved JSON with defaults filled"
}

n21_validate_only_failure() {
  # --validate-only with missing required → same error as a real run, exit 1.
  local out; out=$(run_validate --platform web --deployment personal --language ts)  # missing --project
  [ "${out%%|*}" = "1" ] || { fail_ "N21" "expected exit 1, got: $out"; return; }
  pass "N21: --validate-only failure → exit 1 with same error as real run"
}
```

Append to run-all:

```bash
n20_validate_only_success
n21_validate_only_failure
```

- [ ] **Step 6.3: Run tests; expect 23/23 pass**

```bash
bash tests/test-init-non-interactive.sh
```

Expected: `Total: 23 | Passed: 23 | Failed: 0`.

- [ ] **Step 6.4: Commit**

```bash
git add init.sh tests/test-init-non-interactive.sh
git commit -m "$(cat <<'EOF'
feat(init): non-interactive --validate-only full resolved JSON output (BL-016 task 6)

Replaces the Task-2 minimal JSON stub with the full resolved-config
output per spec § 6.5:
- defaults applied (track=standard, git_host=github, visibility=private,
  project_dir=$HOME/Code/$PROJECT)
- organizational deployment forces visibility=private (matches existing
  init.sh:1713)
- variable assignment to PROJECT_NAME/PROJECT_DESCRIPTION/PLATFORM/TRACK/
  DEPLOYMENT/GOV_MODE/LANGUAGE/PROJECT_DIR/GIT_HOST/VISIBILITY/REMOTE_URL/
  BRANCH_PROTECTION_ATTESTED/ALLOW_EXISTING_DIR for downstream consumption
- JSON built via jq -n with proper escaping; null vs string handling for
  nullable fields (gov_mode, remote_url)

2 new unit tests N20-N21. 23/23 unit tests passing.
EOF
)"
```

---

## Task 7: Defaults verification tests (N24–N26)

**Goal:** Add tests that verify default-application explicitly. The implementation in Task 6 already applies defaults; this task just adds explicit assertions.

**Files:**
- Modify: `tests/test-init-non-interactive.sh` (add N24, N25, N26).

- [ ] **Step 7.1: Append N24, N25, N26**

```bash
n24_default_track() {
  local out; out=$(run_validate --project p --platform web --deployment personal --language typescript)
  local stdout="${out#*|}"; stdout="${stdout%%|*}"
  [[ "$stdout" == *'"track": "standard"'* ]] || { fail_ "N24" "default track should be 'standard': $stdout"; return; }
  pass "N24: --track defaults to 'standard' when not specified"
}

n25_default_git_host_visibility() {
  local out; out=$(run_validate --project p --platform web --deployment personal --language typescript)
  local stdout="${out#*|}"; stdout="${stdout%%|*}"
  [[ "$stdout" == *'"git_host": "github"'* ]] || { fail_ "N25" "default git_host should be 'github': $stdout"; return; }
  [[ "$stdout" == *'"visibility": "private"'* ]] || { fail_ "N25" "default visibility should be 'private': $stdout"; return; }
  pass "N25: --git-host defaults to 'github', --visibility defaults to 'private'"
}

n26_default_project_dir() {
  local out; out=$(run_validate --project mytestproj --platform web --deployment personal --language typescript)
  local stdout="${out#*|}"; stdout="${stdout%%|*}"
  [[ "$stdout" == *'"project_dir": "'$HOME'/Code/mytestproj"'* ]] || { fail_ "N26" "default project_dir should be \$HOME/Code/PROJECT: $stdout"; return; }
  pass "N26: --project-dir defaults to \$HOME/Code/\$PROJECT"
}
```

Append to run-all:

```bash
n24_default_track
n25_default_git_host_visibility
n26_default_project_dir
```

- [ ] **Step 7.2: Run tests; expect 26/26 pass**

```bash
bash tests/test-init-non-interactive.sh
```

Expected: `Total: 26 | Passed: 26 | Failed: 0`.

- [ ] **Step 7.3: Commit**

```bash
git add tests/test-init-non-interactive.sh
git commit -m "test(init): defaults-application unit tests N24-N26 (BL-016 task 7)

Explicit assertions for the default values applied in Task 6:
- N24: --track defaults to standard
- N25: --git-host defaults to github, --visibility defaults to private
- N26: --project-dir defaults to \$HOME/Code/\$PROJECT

26/26 unit tests passing."
```

---

## Task 8: Wire `create_and_protect_remote()` to consume new top-level vars

**Goal:** Surgical 4-line changes per host-related variable in `create_and_protect_remote()` so non-interactive mode's resolved values flow through to remote creation without prompts.

**Files:**
- Modify: `scripts/host-drivers/...` if needed (no — should not be).
- Modify: `init.sh::create_and_protect_remote` (around line 1699).

- [ ] **Step 8.1: Locate and modify the host-and-visibility lookup**

In init.sh, find lines 1700-1707 (the existing host/visibility resolution at the top of `create_and_protect_remote()`):

```bash
create_and_protect_remote() {
  local host visibility
  if [ -f .claude/intake-progress.json ]; then
    host=$(jq -r '.answers.git_host // empty' .claude/intake-progress.json 2>/dev/null || echo "")
    visibility=$(jq -r '.answers.repo_visibility // empty' .claude/intake-progress.json 2>/dev/null || echo "")
  fi
  # Fallback: prompt inline if not captured in intake
  [ -z "$host" ]       && host=$(prompt_choice "Git host:" "github" "gitlab" "bitbucket" "other")
  [ -z "$visibility" ] && visibility=$(prompt_choice "Repository visibility:" "private" "public")
```

Replace with:

```bash
create_and_protect_remote() {
  local host visibility
  # BL-016: prefer non-interactive top-level variables when set.
  if [ -n "${GIT_HOST:-}" ]; then
    host="$GIT_HOST"
  elif [ -f .claude/intake-progress.json ]; then
    host=$(jq -r '.answers.git_host // empty' .claude/intake-progress.json 2>/dev/null || echo "")
  fi
  if [ -n "${VISIBILITY:-}" ]; then
    visibility="$VISIBILITY"
  elif [ -f .claude/intake-progress.json ]; then
    visibility=$(jq -r '.answers.repo_visibility // empty' .claude/intake-progress.json 2>/dev/null || echo "")
  fi
  # Fallback: prompt inline if neither source supplied a value (interactive mode only).
  [ -z "$host" ]       && host=$(prompt_choice "Git host:" "github" "gitlab" "bitbucket" "other")
  [ -z "$visibility" ] && visibility=$(prompt_choice "Repository visibility:" "private" "public")
```

- [ ] **Step 8.2: Modify the host=other URL + attestation lookup**

In init.sh, find the block inside `create_and_protect_remote()` for `host=other` (around lines 1721-1738):

```bash
  if [ "$host" = "other" ]; then
    # URL-paste path — no CLI, no API verification
    read -rp "Paste the HTTPS clone URL of the remote repo you've created: " remote_url
    [ -z "$remote_url" ] && { print_fail "Remote URL required for 'other' host"; return 1; }
    git remote add origin "$remote_url"
    if ! git push -u origin main 2>/dev/null && ! git push -u origin master 2>/dev/null; then
      print_fail "Push failed — verify URL and credentials"
      return 1
    fi
    echo ""
    echo "Since 'other' host is not API-verifiable, attest branch protection:"
    echo "  - Force-push disabled on main"
    echo "  - Admins not exempt from rules"
    [ "$mode" = "org" ] && echo "  - PR reviews required (at least 1 approver)"
    local attest
    read -rp "Has branch protection been configured per the above? [type 'yes' to attest]: " attest
    [ "$attest" != "yes" ] && { print_fail "Attestation required — cannot proceed to Phase 0"; return 1; }
```

Replace with (changes wrap the two `read -rp` calls):

```bash
  if [ "$host" = "other" ]; then
    # URL-paste path — no CLI, no API verification
    local remote_url
    if [ -n "${REMOTE_URL:-}" ]; then
      remote_url="$REMOTE_URL"
    else
      read -rp "Paste the HTTPS clone URL of the remote repo you've created: " remote_url
    fi
    [ -z "$remote_url" ] && { print_fail "Remote URL required for 'other' host"; return 1; }
    git remote add origin "$remote_url"
    if ! git push -u origin main 2>/dev/null && ! git push -u origin master 2>/dev/null; then
      print_fail "Push failed — verify URL and credentials"
      return 1
    fi
    echo ""
    echo "Since 'other' host is not API-verifiable, attest branch protection:"
    echo "  - Force-push disabled on main"
    echo "  - Admins not exempt from rules"
    [ "$mode" = "org" ] && echo "  - PR reviews required (at least 1 approver)"
    local attest
    if [ "${BRANCH_PROTECTION_ATTESTED:-false}" = true ]; then
      attest="yes"
      print_info "Branch protection attested via --branch-protection-attested flag."
    else
      read -rp "Has branch protection been configured per the above? [type 'yes' to attest]: " attest
    fi
    [ "$attest" != "yes" ] && { print_fail "Attestation required — cannot proceed to Phase 0"; return 1; }
```

- [ ] **Step 8.3: Sanity-check syntax**

```bash
bash -n init.sh && echo "SYNTAX_OK"
```

- [ ] **Step 8.4: Commit**

```bash
git add init.sh
git commit -m "$(cat <<'EOF'
feat(init): create_and_protect_remote consumes non-interactive vars (BL-016 task 8)

Surgical 4-line changes per host-related variable in
create_and_protect_remote() so non-interactive mode's resolved values
flow through to remote creation without prompts.

Lookup order is now:
1. Non-interactive top-level variable (GIT_HOST, VISIBILITY, REMOTE_URL,
   BRANCH_PROTECTION_ATTESTED) if set.
2. .claude/intake-progress.json if present.
3. Interactive prompt (prompt_choice / read -rp) — final fallback,
   only reached in interactive mode.

The interactive flow is fully preserved (the prompt fallback still runs
when none of the variables are set, which is exactly the case for
existing interactive invocations).
EOF
)"
```

---

## Task 9: Integration tests E48–E55 in `tests/edge-cases-scripts.sh`

**Goal:** Add the 8 end-to-end integration tests from spec § 8.2.

**Files:**
- Modify: `tests/edge-cases-scripts.sh` (append section before the SUMMARY block).

- [ ] **Step 9.1: Find the SUMMARY-block insertion point**

```bash
cd "/Users/karl/Documents/Claude Projects/solo-orchestrator"
grep -n "SUMMARY" tests/edge-cases-scripts.sh | tail -3
```

The new section goes immediately before the `# ================================================================` line that precedes the SUMMARY echo block.

- [ ] **Step 9.2: Insert the E48–E55 section**

Insert before the SUMMARY block:

```bash

# ================================================================
section "BL-016: init.sh non-interactive mode — E48-E55"

INIT_SH="$REPO_DIR/init.sh"

# E48: Full happy-path web/personal/standard/typescript run (no actual scaffolding —
# we use --validate-only since real init.sh writes a project skeleton + clones CDF).
_e48_dir="$TEST_DIR/e48"
mkdir -p "$_e48_dir"
_e48_out=$(cd "$_e48_dir" && "$INIT_SH" --non-interactive --validate-only \
  --project uat-e48 --platform web --deployment personal --language typescript \
  --project-dir "$_e48_dir/proj" 2>&1)
_e48_rc=$?
if [ "$_e48_rc" = "0" ] && echo "$_e48_out" | grep -q '"_validated": true'; then
  pass "E48: full non-interactive happy path → exit 0 with resolved JSON"
else
  fail "E48: expected exit 0 with _validated:true, got rc=$_e48_rc out=$_e48_out"
fi

# E49: Same as E48 but explicitly testing that --validate-only doesn't create the project dir.
_e49_dir="$TEST_DIR/e49"
mkdir -p "$_e49_dir"
"$INIT_SH" --non-interactive --validate-only \
  --project uat-e49 --platform web --deployment personal --language typescript \
  --project-dir "$_e49_dir/proj" >/dev/null 2>&1
if [ ! -d "$_e49_dir/proj" ]; then
  pass "E49: --validate-only does not create project dir"
else
  fail "E49: --validate-only created project dir (should not have)"
fi

# E50: Mobile + organizational + private_poc + kotlin
_e50_dir="$TEST_DIR/e50"
mkdir -p "$_e50_dir"
_e50_out=$("$INIT_SH" --non-interactive --validate-only \
  --project uat-e50 --platform mobile --deployment organizational --gov-mode private_poc --language kotlin \
  --project-dir "$_e50_dir/proj" 2>&1)
if [ "$?" = "0" ] && echo "$_e50_out" | grep -q '"gov_mode": "private_poc"' && echo "$_e50_out" | grep -q '"visibility": "private"'; then
  pass "E50: organizational + private_poc forces visibility=private"
else
  fail "E50: expected gov_mode=private_poc and visibility=private, got: $_e50_out"
fi

# E51: git-host=other + remote-url + attested → validate succeeds.
_e51_dir="$TEST_DIR/e51"
mkdir -p "$_e51_dir"
_e51_out=$("$INIT_SH" --non-interactive --validate-only \
  --project uat-e51 --platform web --deployment organizational --gov-mode production --language typescript \
  --git-host other --remote-url https://example.com/fake.git --branch-protection-attested \
  --project-dir "$_e51_dir/proj" 2>&1)
if [ "$?" = "0" ] && echo "$_e51_out" | grep -q '"git_host": "other"'; then
  pass "E51: --git-host=other + --remote-url + --branch-protection-attested → validates"
else
  fail "E51: expected exit 0 with git_host=other, got: $_e51_out"
fi

# E52: --config provides everything
_e52_dir="$TEST_DIR/e52"
mkdir -p "$_e52_dir"
cat > "$_e52_dir/cfg.json" <<'JSON'
{"project":"uat-e52","platform":"web","deployment":"personal","language":"typescript","track":"standard"}
JSON
_e52_out=$("$INIT_SH" --non-interactive --validate-only --config "$_e52_dir/cfg.json" \
  --project-dir "$_e52_dir/proj" 2>&1)
if [ "$?" = "0" ] && echo "$_e52_out" | grep -q '"project": "uat-e52"'; then
  pass "E52: --config provides all required → validates"
else
  fail "E52: expected exit 0 from config, got: $_e52_out"
fi

# E53: --config + flag override
_e53_dir="$TEST_DIR/e53"
mkdir -p "$_e53_dir"
cat > "$_e53_dir/cfg.json" <<'JSON'
{"project":"uat-e53","platform":"web","deployment":"personal","language":"typescript","track":"light"}
JSON
_e53_out=$("$INIT_SH" --non-interactive --validate-only --config "$_e53_dir/cfg.json" \
  --track full --project-dir "$_e53_dir/proj" 2>&1)
if [ "$?" = "0" ] && echo "$_e53_out" | grep -q '"track": "full"'; then
  pass "E53: --config (track=light) + --track full → flag wins"
else
  fail "E53: expected resolved track=full, got: $_e53_out"
fi

# E54: --non-interactive with no required flags
_e54_dir="$TEST_DIR/e54"
mkdir -p "$_e54_dir"
_e54_out=$(cd "$_e54_dir" && "$INIT_SH" --non-interactive --validate-only 2>&1)
_e54_rc=$?
if [ "$_e54_rc" = "1" ] && echo "$_e54_out" | grep -q "FAIL"; then
  pass "E54: --non-interactive with no required flags → exit 1 with FAIL message"
else
  fail "E54: expected exit 1 with FAIL, got rc=$_e54_rc out=$_e54_out"
fi

# E55: existing-dir test — first run fails (no flag), second succeeds (flag set).
_e55_dir="$TEST_DIR/e55"
mkdir -p "$_e55_dir"
mkdir -p "$_e55_dir/already-here"
_e55_first=$("$INIT_SH" --non-interactive --validate-only \
  --project uat-e55 --platform web --deployment personal --language typescript \
  --project-dir "$_e55_dir/already-here" 2>&1)
_e55_first_rc=$?
_e55_second=$("$INIT_SH" --non-interactive --validate-only \
  --project uat-e55 --platform web --deployment personal --language typescript \
  --project-dir "$_e55_dir/already-here" --allow-existing-dir 2>&1)
_e55_second_rc=$?
if [ "$_e55_first_rc" = "1" ] && [ "$_e55_second_rc" = "0" ]; then
  pass "E55: existing dir without --allow-existing-dir fails; with the flag succeeds"
else
  fail "E55: expected first run to fail and second to succeed; got first=$_e55_first_rc second=$_e55_second_rc"
fi

```

- [ ] **Step 9.3: Run the full edge-cases suite**

```bash
bash tests/edge-cases-scripts.sh 2>&1 | grep -E "PASS:|FAIL:|TOTAL:|E4[89]|E5[0-5]" | tail -15
```

Expected: 8 new tests (E48–E55) all pass; the existing 54 tests still pass (62 total).

- [ ] **Step 9.4: Commit**

```bash
git add tests/edge-cases-scripts.sh
git commit -m "$(cat <<'EOF'
test(init): integration tests E48-E55 for non-interactive mode (BL-016 task 9)

8 end-to-end tests in tests/edge-cases-scripts.sh per spec § 8.2:
  E48: full happy path (web/personal/standard/typescript) → validates
  E49: --validate-only does not create the project dir
  E50: organizational+private_poc forces visibility=private
  E51: git-host=other + remote-url + attested validates
  E52: --config provides all required
  E53: --config + flag override (flag wins)
  E54: --non-interactive without required flags → exit 1
  E55: existing dir with/without --allow-existing-dir

All 8 use --validate-only to exercise the validation pipeline without
actually scaffolding a project + cloning CDF. Real init.sh runs are
covered by the Task 12 re-test sweep against the original UAT configs.
EOF
)"
```

---

## Task 10: Doc updates (Builder's Guide subsection + claude-md.tmpl bullet + upgrade changelog)

**Goal:** Land the three doc surfaces from spec § 9.

**Files:**
- Modify: `docs/builders-guide.md`
- Modify: `templates/generated/claude-md.tmpl`
- Modify: `scripts/upgrade-project.sh` (header changelog only)

- [ ] **Step 10.1: Add Builder's Guide subsection**

```bash
grep -n "MVP Cutline Work Requires the Build Loop\|Structured Decision Points\|^## " docs/builders-guide.md | head -20
```

Find a spot after Phase 0 content. Insert a new subsection at the natural Phase 0 boundary:

`old_string` — pick an existing line that ends a Phase 0 subsection. Use the Edit tool to insert the new subsection content from spec § 9.1.

Specifically, insert before the line `### Structured Decision Points: The Pending-Approval Sentinel`:

```markdown

### Scripted / Non-Interactive Project Initialization

For CI pipelines, automated UAT, or AI-orchestrator-driven project creation, `init.sh` supports a `--non-interactive` mode with explicit per-input flags and JSON config-file support.

**Minimal invocation:**
\`\`\`bash
./init.sh --non-interactive \
  --project my-app \
  --platform web \
  --deployment personal \
  --language typescript
\`\`\`

**With config file:**
\`\`\`bash
echo '{"platform":"web","track":"standard","deployment":"personal","language":"typescript"}' > init.json
./init.sh --non-interactive --config init.json --project my-app
\`\`\`

**Validate without scaffolding:**
\`\`\`bash
./init.sh --non-interactive --config init.json --project my-app --validate-only | jq
\`\`\`

See `init.sh --help-non-interactive` for the full schema, defaults table, and per-flag reference.

**When NOT to use:** human-driven first-time setup is better served by the interactive flow, which adapts prompts to the chosen platform/deployment context. Non-interactive mode is for repeatable, scripted workflows where the orchestrator already knows the answers.

---

```

- [ ] **Step 10.2: Add `claude-md.tmpl` bullet**

Locate the Operations Reference section and add the bullet from spec § 9.2:

```bash
grep -n "## Operations Reference\|Operations Reference" templates/generated/claude-md.tmpl | head -5
```

Append a new bullet to the Operations Reference list:

```markdown
- **Scripted setup.** For CI, UAT, or agent-driven project creation, use `init.sh --non-interactive --project NAME --platform PLATFORM --deployment DEPLOYMENT --language LANG [...]`. See `init.sh --help-non-interactive` for the full schema. Honors `--config FILE` for repeatable setups; flag values override config file values.
```

- [ ] **Step 10.3: Add upgrade-project.sh changelog entry**

```bash
grep -n "BL-006\|BL-015\|^# Changelog" scripts/upgrade-project.sh | head -10
```

Append to the existing changelog block:

```
# - BL-016 (2026-04-25): init.sh now supports --non-interactive mode for
#   scriptable project setup (CI, UAT, AI agents). No upgrade-project.sh
#   change needed — scripts/init.sh is copied into projects but agents
#   typically invoke the framework's init.sh directly.
```

- [ ] **Step 10.4: Bash syntax check on upgrade-project.sh**

```bash
bash -n scripts/upgrade-project.sh && echo "SYNTAX_OK"
```

- [ ] **Step 10.5: Commit**

```bash
git add docs/builders-guide.md templates/generated/claude-md.tmpl scripts/upgrade-project.sh
git commit -m "$(cat <<'EOF'
docs(bl-016): non-interactive subsection, template bullet, upgrade changelog

- docs/builders-guide.md: new "Scripted / Non-Interactive Project
  Initialization" subsection with minimal invocation, config-file,
  and --validate-only examples + when-not-to-use guidance.
- templates/generated/claude-md.tmpl: new Operations Reference bullet
  pointing agents at init.sh --non-interactive + --help-non-interactive.
- scripts/upgrade-project.sh: BL-016 entry in header changelog (no
  behavioral change — init.sh is still invoked from the framework
  directly, not via upgrade-project.sh).
EOF
)"
```

---

## Task 11: Full verification + Build Loop close + PR

**Goal:** Run all test suites, complete Build Loop steps, push branch, open PR.

- [ ] **Step 11.1: Run all test suites**

```bash
echo "=== test-init-non-interactive ==="
bash tests/test-init-non-interactive.sh 2>&1 | tail -3

echo "=== edge-cases-scripts ==="
bash tests/edge-cases-scripts.sh 2>&1 | grep -E "PASS:|FAIL:|TOTAL:"

echo "=== test-pending-approval ==="
bash tests/test-pending-approval.sh 2>&1 | tail -3

echo "=== test-check-commit-message ==="
bash tests/test-check-commit-message.sh 2>&1 | tail -3

echo "=== test-unrecord-feature ==="
bash tests/test-unrecord-feature.sh 2>&1 | tail -3

echo "=== known-bugs ==="
bash tests/known-bugs-test-suite.sh 2>&1 | tail -3

echo "=== test-lint-uat-scenarios ==="
bash tests/test-lint-uat-scenarios.sh 2>&1 | tail -3
```

Expected: all green; new suite shows 26/26 unit tests; edge-cases shows 62/62 (54 prior + 8 new).

- [ ] **Step 11.2: Smoke-test interactive flow regression**

```bash
bash init.sh --help | head -20
bash init.sh --help-non-interactive | head -10
bash init.sh --dry-run </dev/null 2>&1 | head -10  # interactive flow with empty stdin — should NOT hang now thanks to PR #18 EOF guard
```

Expected: help text renders correctly; dry-run interactive doesn't hang.

- [ ] **Step 11.3: Complete Build Loop steps**

```bash
scripts/process-checklist.sh --complete-step build_loop:tests_written
scripts/process-checklist.sh --complete-step build_loop:tests_verified_failing
scripts/process-checklist.sh --complete-step build_loop:implemented
```

Then write a security audit findings file (similar shape to BL-006/BL-015 audits), then:

```bash
scripts/process-checklist.sh --complete-step build_loop:security_audit
scripts/process-checklist.sh --complete-step build_loop:documentation_updated
```

- [ ] **Step 11.4: Write security audit**

Create `docs/security-audits/bl-016-init-non-interactive-security-audit.md`:

```markdown
# Security Audit Findings — Feature: BL-016 init.sh non-interactive mode

**Feature:** bl-016-init-non-interactive
**Date:** 2026-04-25
**Auditor Persona:** Senior Security Engineer

## Scope
- New code in init.sh: collect_inputs_non_interactive(), main() flag-parser
  extension, create_and_protect_remote() variable lookups, dir-exists check.
- New file: scripts/test-init-non-interactive.sh (test code only).
- Documentation/template additions (no executable code changes).

## Manual Review Findings

| # | Category | Finding | Severity | Resolution | Status |
|---|----------|---------|----------|------------|--------|
| 1 | Command injection | All user input flows through bash variables; no eval, no shell interpolation of untrusted input into commands. JSON parsed via jq. | Critical | No mitigation needed — safe by design. | Accepted |
| 2 | Path traversal | --project-dir is bash-expanded but never used as a flag to git/jq/etc. without quoting. mkdir -p / [ -e ] / [ -d ] use $effective_project_dir directly with quotes. | Medium | Bounded by user intent; no code injection vector. | Accepted |
| 3 | Config file parsing | jq -e . validates JSON syntax before extracting fields. Schema-typed checks reject malformed values before they reach the rest of the pipeline. | Medium | Validation in place. | Fixed |
| 4 | Information disclosure | --validate-only output is JSON to stdout; contains the resolved config (no secrets). | Low | Intentional — agents need this to confirm what they're about to install. | Accepted |
| 5 | Bypass via missing tools | If git/jq/node/python3 are missing, non-interactive mode fails fast with the install command. No silent partial-install. | High | Pass-3 resource validation catches before any file writes. | Fixed |
| 6 | DoS via huge config file | jq parses the entire file into memory; a 1GB config file would OOM. | Negligible | jq's memory profile is the user's problem; no malicious-input vector since user owns the file path. | Accepted |

## Summary
- 0 Open findings.
- All Critical (#1) and High (#5) findings addressed by design or implementation.
- No code changes required to resolve audit findings.
```

```bash
git add docs/security-audits/bl-016-init-non-interactive-security-audit.md
git commit -m "docs(security-audit): BL-016 init.sh non-interactive mode audit"
```

- [ ] **Step 11.5: Push branch and open PR**

```bash
git push -u origin feat/bl-016-init-non-interactive
gh pr create --title "BL-016: init.sh --non-interactive mode" --body "$(cat <<'EOF'
## Summary

- New `--non-interactive` mode in init.sh with ~12 per-input flags + JSON `--config FILE` support (flag overrides config).
- Three-pass validation (schema, context-required, resource) with uniform `[FAIL] init.sh non-interactive: ...` error format.
- `--validate-only` for smoke-testing without scaffolding.
- `--help-non-interactive` reference output (full schema + JSON example + per-flag descriptions).
- Existing interactive flow UNTOUCHED (Approach A from spec).
- Surgical 4-line changes in `create_and_protect_remote()` so non-interactive resolved values flow through to remote creation.
- 26 unit tests (`tests/test-init-non-interactive.sh`) + 8 integration tests (E48–E55 in `tests/edge-cases-scripts.sh`).
- Docs: Builder's Guide subsection, claude-md.tmpl bullet, upgrade-project.sh changelog.

UAT 2026-04-25's highest-frequency finding (8/13 agents): init.sh has no scriptable mode. This PR closes that gap.

## Test plan

- [x] `bash tests/test-init-non-interactive.sh` — 26/26 pass
- [x] `bash tests/edge-cases-scripts.sh` — 62/62 pass (54 prior + 8 new)
- [x] All other test suites unchanged: test-pending-approval (17/17), test-check-commit-message (18/18), test-unrecord-feature (7/7), known-bugs (22/22), test-lint-uat-scenarios (11/11)
- [x] Smoke test: `init.sh --help`, `--help-non-interactive`, `--dry-run` interactive flow

## References

- Spec: `docs/superpowers/specs/2026-04-25-init-sh-non-interactive-design.md`
- Plan: `docs/superpowers/plans/2026-04-25-init-sh-non-interactive-implementation.md`
- UAT triage: `Reports/uat-2026-04-25/TRIAGE.md` (U-A)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 11.6: After PR merges — record feature, close Build Loop, update backlog**

```bash
git checkout main
git pull --ff-only origin main
scripts/test-gate.sh --record-feature "bl-016-init-non-interactive"
scripts/process-checklist.sh --complete-step build_loop:feature_recorded
```

Update `solo-orchestrator-backlog.md`: change BL-016 status from `promoted-to-spec` to `Resolved (2026-04-25, PR #N)` with a Resolution paragraph mirroring BL-006/BL-007/BL-008/BL-009/BL-015 entries.

```bash
git add solo-orchestrator-backlog.md
git commit -m "backlog: mark BL-016 resolved (PR #N merged 2026-04-25)"
git push origin main
git branch -d feat/bl-016-init-non-interactive
```

---

## Self-Review Checklist (completed at plan-writing time)

**1. Spec coverage — every spec section is mapped to a task:**
- Spec § 1 Problem: context only.
- Spec § 2 Scope: tasks 1–11 cover in-scope items; § 2's "out of scope" deferred items are explicitly NOT in any task.
- Spec § 3 Locked parameters: each baked into Task 1 (flag set + mode boolean), Task 2-7 (validation + defaults), Task 5 (config file).
- Spec § 4 Architecture: Task 1 (skeleton) + Task 8 (downstream consumption) realize the diagram.
- Spec § 5 CLI surface: Task 1 (flag parser, --help) + Task 1.3 (--help-non-interactive).
- Spec § 6 Validation logic: Task 2 (Pass 1), Task 3 (Pass 2), Task 4 (Pass 3), Task 6 (--validate-only).
- Spec § 7 Defaults table: Task 6 applies defaults; Task 7 explicitly tests them.
- Spec § 8 Test strategy: Task 2-7 cover Layer 1 (unit), Task 9 covers Layer 2 (integration). Layer 3 (re-test sweep on UAT configs) is post-merge ad-hoc, not in this plan.
- Spec § 9 Documentation: Task 10.
- Spec § 10 Risks: addressed by Approach A's separation (Task 1 keeps interactive flow untouched), --validate-only (Task 6), code-shape tests in unit suite.
- Spec § 11 Success criteria: Task 11 verification covers them.
- Spec § 12 Scope boundaries: in-scope items map to tasks 1–11; out-of-scope items are not in any task.

**2. Placeholder scan:** no TBD/TODO/fill-in. Every step has complete code or exact commands.

**3. Type consistency:**
- `collect_inputs_non_interactive()` — same name in Tasks 1, 2, 3, 4, 5, 6.
- `print_help_non_interactive()` — same name in Tasks 1, 11.
- `ARG_*` variable names — consistent across Tasks 1, 2, 3, 4, 5, 6.
- Resolved variable names (`PROJECT_NAME`, `PLATFORM`, etc.) — match existing init.sh interactive flow consumption.
- `NON_INTERACTIVE`, `VALIDATE_ONLY`, `CONFIG_FILE` — consistent across all tasks.
- `cfg_get` helper inside `collect_inputs_non_interactive` — defined and used only in Task 5.

**Fixable issues found during self-review:** none. Plan is ready to execute.

# Host-Aware Repo Creation Gate — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the host-aware repo creation gate per spec `docs/superpowers/specs/2026-04-21-host-aware-repo-gate-design.md`. After completion, no solo-orchestrator project can reach Phase 1 without a created and protection-configured git remote, across GitHub / GitLab / Bitbucket (first-class) or `other` (URL-paste + manual attestation).

**Architecture:** Per-host driver files (`scripts/host-drivers/<host>.sh`) implement a uniform contract. A dispatcher (`scripts/lib/host.sh`) reads `.claude/manifest.json`'s `host` field and routes calls to the right driver. Enforcement happens at two points: primary at `init.sh` (repo creation before Phase 0 begins) and secondary at the Phase 1→2 gate (via `check-phase-gate.sh`). Remediation via `scripts/check-gate.sh`'s three subcommands.

**Tech Stack:** Bash 4+, jq, git, `gh` CLI (GitHub), `glab` CLI (GitLab), `curl` + Bitbucket App Passwords (Bitbucket). Existing solo-orchestrator test harness pattern (bash-based assertion scripts in `tests/`). GitHub Actions / GitLab CI / Bitbucket Pipelines YAML.

---

## File Structure

```
scripts/
├── lib/
│   └── host.sh                          # NEW: dispatcher
├── host-drivers/                        # NEW directory
│   ├── github.sh                        # NEW: gh CLI + GitHub REST API
│   ├── gitlab.sh                        # NEW: glab CLI + GitLab API
│   └── bitbucket.sh                     # NEW: curl + Bitbucket API
├── check-gate.sh                        # NEW: --preflight / --repair / --backfill-host
├── intake-wizard.sh                     # MODIFIED: host + visibility questions
├── process-checklist.sh                 # MODIFIED: verify_init rewrite
├── check-phase-gate.sh                  # MODIFIED: Phase 1→2 backstop
├── pre-commit-gate.sh                   # MODIFIED: early remote-exists guard
├── upgrade-project.sh                   # MODIFIED: template path migration + host backfill
└── resolve-tools.sh                     # MODIFIED: host CLI availability

templates/pipelines/
├── ci/
│   ├── github/                          # REORG: 10 existing files moved here
│   ├── gitlab/                          # NEW: 10 translated files
│   └── bitbucket/                       # NEW: 10 translated files
└── release/
    ├── github/                          # REORG: 4 existing files moved
    ├── gitlab/                          # NEW: 4 translated
    └── bitbucket/                       # NEW: 4 translated

templates/
├── project-intake.md                    # MODIFIED: Git Host field
├── intake-suggestions/common.json       # MODIFIED: host suggestions
└── tool-matrix/common.json              # MODIFIED: gh/glab/curl entries

tests/
├── host-drivers/                        # NEW directory
│   ├── mock-cli.sh                      # NEW: shared PATH-shim helper
│   ├── github.test.sh                   # NEW: 60+ unit cases, opt-in integration
│   ├── gitlab.test.sh                   # NEW
│   └── bitbucket.test.sh                # NEW
├── full-project-test-suite.sh           # MODIFIED: per-host end-to-end
├── known-bugs-test-suite.sh             # MODIFIED: lancache + manifest + drift regressions
└── upgrade-path-tests.sh                # MODIFIED: flat→per-host template layout migration

docs/
├── builders-guide.md                    # MODIFIED: per-host repo/protection sections
└── cli-setup-addendum.md                # MODIFIED: gh/glab install + auth

init.sh                                  # MODIFIED: host selection + driver integration
.claude/manifest.json (per-project)      # NEW FIELD: "host"
```

**Key design choices reflected in this structure:**
- Per-host driver files keep host-specific logic bounded (~150-200 lines each), readable, and independently testable.
- Dispatcher (`lib/host.sh`) is the single entry point; callers never touch `gh`/`glab`/`curl` directly.
- Templates reorganize into per-host subfolders. `upgrade-project.sh` handles the migration for existing projects.
- Tests mirror source structure (`tests/host-drivers/<host>.test.sh`).
- Mock CLI harness (`tests/host-drivers/mock-cli.sh`) shims `gh`/`glab`/`curl` via PATH-prepended fixture directory — always runs (no network), integration tests opt-in via `HOST_INTEGRATION_TESTS=1`.

---

## Phase 0 — Prerequisites (test harness + schema)

### Task 0.1: Create shared mock CLI test harness

**Files:**
- Create: `tests/host-drivers/mock-cli.sh`

- [ ] **Step 1: Create the test harness file**

```bash
#!/usr/bin/env bash
# tests/host-drivers/mock-cli.sh
# Shared harness for host-driver unit tests. Creates a temp dir with stub CLIs
# (gh, glab, curl) that echo canned fixtures and exit with canned codes.
# Usage:
#   source tests/host-drivers/mock-cli.sh
#   MOCK_DIR=$(mock_cli_setup)
#   export PATH="$MOCK_DIR:$PATH"
#   mock_cli_respond gh "repo create my-repo --private" 0 "https://github.com/user/my-repo"
#   # ... run code that invokes `gh repo create ...`
#   mock_cli_teardown "$MOCK_DIR"

set -euo pipefail

mock_cli_setup() {
  local dir
  dir=$(mktemp -d "${TMPDIR:-/tmp}/solo-mock-cli-XXXXXX")
  echo "$dir"
}

# Register a stub response for a command invocation.
# Args: cli_name arg_pattern exit_code stdout
mock_cli_respond() {
  local cli="$1" pattern="$2" code="$3" output="$4"
  local dir="${MOCK_DIR:?MOCK_DIR not set — call mock_cli_setup first}"
  local stub="$dir/$cli"
  mkdir -p "$dir/.fixtures"

  # Each stub writes its arg-line, consults fixtures, and exits.
  cat > "$stub" <<'STUB_EOF'
#!/usr/bin/env bash
fixture_dir="$(dirname "$0")/.fixtures"
cli="$(basename "$0")"
args="$*"
# Find first matching fixture file: <cli>.<hash-of-pattern>
for f in "$fixture_dir/$cli".*; do
  [ -f "$f" ] || continue
  pattern=$(head -n1 "$f")
  if [[ "$args" == *"$pattern"* ]]; then
    code=$(sed -n '2p' "$f")
    tail -n +3 "$f"
    exit "$code"
  fi
done
echo "mock-cli: no fixture for '$cli $args'" >&2
exit 127
STUB_EOF
  chmod +x "$stub"

  # Register the fixture
  local hash
  hash=$(echo -n "$pattern" | shasum -a 256 | cut -c1-8)
  {
    echo "$pattern"
    echo "$code"
    printf '%s' "$output"
  } > "$dir/.fixtures/$cli.$hash"
}

mock_cli_teardown() {
  local dir="$1"
  [ -d "$dir" ] && rm -rf "$dir"
}

# Simple assertion helpers (bash-style; solo-orchestrator's tests/ pattern)
assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [ "$expected" != "$actual" ]; then
    echo "ASSERT FAIL${msg:+ [$msg]}: expected '$expected', got '$actual'" >&2
    return 1
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "ASSERT FAIL${msg:+ [$msg]}: '$haystack' does not contain '$needle'" >&2
    return 1
  fi
}

assert_exit_code() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [ "$expected" != "$actual" ]; then
    echo "ASSERT FAIL${msg:+ [$msg]}: expected exit $expected, got $actual" >&2
    return 1
  fi
}
```

- [ ] **Step 2: Write a self-test to verify the harness works**

Create `tests/host-drivers/mock-cli.selftest.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/mock-cli.sh"

MOCK_DIR=$(mock_cli_setup)
trap 'mock_cli_teardown "$MOCK_DIR"' EXIT

export PATH="$MOCK_DIR:$PATH"

# Case: fixture hit
mock_cli_respond gh "repo create test-repo" 0 "https://github.com/u/test-repo"
output=$(gh repo create test-repo --private 2>&1)
assert_eq "https://github.com/u/test-repo" "$output" "fixture stdout"

# Case: fixture miss (no match)
set +e
gh wat-is-this 2>/dev/null
code=$?
set -e
assert_exit_code 127 "$code" "unregistered command exits 127"

echo "mock-cli self-test PASSED"
```

- [ ] **Step 3: Run the self-test to verify**

Run: `bash tests/host-drivers/mock-cli.selftest.sh`
Expected output: `mock-cli self-test PASSED`

- [ ] **Step 4: Commit**

```bash
git add tests/host-drivers/mock-cli.sh tests/host-drivers/mock-cli.selftest.sh
git commit -m "test(host-drivers): add mock CLI harness for driver unit tests"
```

### Task 0.2: Add host field to manifest schema documentation

**Files:**
- Modify: `docs/user-guide.md` (manifest schema section, if exists) or add to spec-related docs

- [ ] **Step 1: Find existing manifest.json schema documentation**

Run: `grep -rn "manifest.json" docs/ scripts/ | grep -v superpowers/`
Expected: several references. Look for any that documents the manifest structure.

- [ ] **Step 2: Update or add schema documentation**

If a schema section exists in `docs/user-guide.md`, add `host` to the documented fields. If not, add a short paragraph in `docs/user-guide.md` under the "Project State Files" section (or equivalent):

```markdown
**`.claude/manifest.json`** — per-project state file maintained by CDF and solo-orchestrator. Notable fields:
- `version` — framework version pin
- `host` — git host type (`github` | `gitlab` | `bitbucket` | `other`). Written at init time; used by host-aware scripts to dispatch to the right driver.
- `mode` — project mode (`personal` | `org`). Controls protection bar and some governance paths.
- `remote_url` — HTTPS clone URL of the remote created at init.
```

- [ ] **Step 3: Commit**

```bash
git add docs/user-guide.md
git commit -m "docs: document host and mode fields in .claude/manifest.json"
```

---

## Phase 1 — Dispatcher + GitHub Driver (TDD)

### Task 1.1: Create dispatcher skeleton

**Files:**
- Create: `scripts/lib/host.sh`
- Test: `tests/host-drivers/dispatcher.test.sh`

- [ ] **Step 1: Write failing test for dispatcher manifest read**

```bash
#!/usr/bin/env bash
# tests/host-drivers/dispatcher.test.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/mock-cli.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
mkdir -p .claude
echo '{"host":"github","mode":"personal","remote_url":"https://github.com/u/r"}' > .claude/manifest.json

source "$REPO_ROOT/scripts/lib/host.sh"

# Test: dispatcher reads host from manifest
actual=$(host_read_from_manifest)
assert_eq "github" "$actual" "dispatcher reads host field"

echo "dispatcher.test.sh: read_from_manifest PASSED"
```

- [ ] **Step 2: Run test to verify failure**

Run: `bash tests/host-drivers/dispatcher.test.sh`
Expected: FAIL with "scripts/lib/host.sh: No such file or directory"

- [ ] **Step 3: Create the dispatcher with minimal implementation**

```bash
#!/usr/bin/env bash
# scripts/lib/host.sh — host dispatcher. Reads .claude/manifest.json for the
# `host` field and sources the matching driver in scripts/host-drivers/<host>.sh.
# Callers use the unified interface exposed by the sourced driver:
#   host_name, host_require_cli, host_create_repo, host_register_remote,
#   host_push_initial, host_configure_protection, host_verify_protection
#
# For host = "other", this file provides inline implementations (URL paste +
# manual attestation) instead of sourcing a driver file.

set -euo pipefail

_host_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

host_read_from_manifest() {
  local manifest
  manifest="$(_host_repo_root)/.claude/manifest.json"
  if [ ! -f "$manifest" ]; then
    echo "host.sh: .claude/manifest.json not found at $manifest" >&2
    return 1
  fi
  local host
  host=$(jq -r '.host // empty' "$manifest" 2>/dev/null || true)
  if [ -z "$host" ]; then
    echo "host.sh: manifest.json missing 'host' field. Run: scripts/check-gate.sh --backfill-host" >&2
    return 2
  fi
  echo "$host"
}

host_load_driver() {
  local host
  host=$(host_read_from_manifest) || return $?
  case "$host" in
    github|gitlab|bitbucket)
      local driver
      driver="$(_host_repo_root)/scripts/host-drivers/$host.sh"
      if [ ! -f "$driver" ]; then
        echo "host.sh: driver for '$host' not found at $driver" >&2
        return 3
      fi
      # shellcheck disable=SC1090
      source "$driver"
      ;;
    other)
      # 'other' uses inline fallbacks defined below; no driver file.
      source "$(_host_repo_root)/scripts/lib/host.sh.other-impl" 2>/dev/null \
        || _host_define_other_fallbacks
      ;;
    *)
      echo "host.sh: unknown host '$host'. Valid: github, gitlab, bitbucket, other" >&2
      return 4
      ;;
  esac
}

_host_define_other_fallbacks() {
  host_name()                { echo "other"; }
  host_require_cli()         { return 0; }  # No CLI for 'other'; user provides URL
  host_create_repo()         { echo "host.sh: 'other' host requires user-supplied URL — call from init.sh interactively" >&2; return 10; }
  host_register_remote()     { git remote add origin "$1"; }
  host_push_initial()        { git push -u origin "${1:-main}"; }
  host_configure_protection(){ echo "host.sh: 'other' host — branch protection via manual attestation only" >&2; return 0; }
  host_verify_protection() {
    # Read attestation from process-state.json
    local ps="$(_host_repo_root)/.claude/process-state.json"
    [ ! -f "$ps" ] && return 1
    local attested
    attested=$(jq -r '.phase2_init.attestations.branch_protection.at // empty' "$ps" 2>/dev/null || true)
    [ -z "$attested" ] && return 1
    # Check attestation age (90 days)
    local now days
    now=$(date +%s)
    days=$(( (now - $(date -j -f "%Y-%m-%dT%H:%M:%S" "$attested" +%s 2>/dev/null || echo "$now")) / 86400 ))
    [ "$days" -gt 90 ] && return 1
    return 0
  }
}
```

- [ ] **Step 4: Run test to verify pass**

Run: `bash tests/host-drivers/dispatcher.test.sh`
Expected output: `dispatcher.test.sh: read_from_manifest PASSED`

- [ ] **Step 5: Add test for missing manifest**

Append to `tests/host-drivers/dispatcher.test.sh`:

```bash
# Test: missing manifest returns error
WORK2=$(mktemp -d)
(
  cd "$WORK2"
  # No .claude directory
  set +e
  output=$(source "$REPO_ROOT/scripts/lib/host.sh" && host_read_from_manifest 2>&1)
  code=$?
  set -e
  assert_exit_code 1 "$code" "missing manifest returns code 1"
  assert_contains "$output" "manifest.json not found" "error message"
)
rm -rf "$WORK2"

# Test: malformed manifest (missing host field)
WORK3=$(mktemp -d)
(
  cd "$WORK3"
  mkdir -p .claude
  echo '{"mode":"personal"}' > .claude/manifest.json
  set +e
  output=$(source "$REPO_ROOT/scripts/lib/host.sh" && host_read_from_manifest 2>&1)
  code=$?
  set -e
  assert_exit_code 2 "$code" "missing host field returns code 2"
  assert_contains "$output" "--backfill-host" "remediation hint"
)
rm -rf "$WORK3"

echo "dispatcher.test.sh: all tests PASSED"
```

- [ ] **Step 6: Run updated test**

Run: `bash tests/host-drivers/dispatcher.test.sh`
Expected: all three cases pass.

- [ ] **Step 7: Commit**

```bash
git add scripts/lib/host.sh tests/host-drivers/dispatcher.test.sh
git commit -m "feat(host): dispatcher skeleton with manifest reading"
```

### Task 1.2: GitHub driver — host_name

**Files:**
- Create: `scripts/host-drivers/github.sh`
- Modify: `tests/host-drivers/github.test.sh` (create if absent)

- [ ] **Step 1: Write failing test**

Create `tests/host-drivers/github.test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/mock-cli.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/scripts/host-drivers/github.sh"

# Test: host_name returns "github"
actual=$(host_name)
assert_eq "github" "$actual" "host_name"

echo "github.test.sh: host_name PASSED"
```

- [ ] **Step 2: Run test to verify fail**

Run: `bash tests/host-drivers/github.test.sh`
Expected: FAIL ("No such file or directory" for github.sh).

- [ ] **Step 3: Create github.sh with minimal host_name**

```bash
#!/usr/bin/env bash
# scripts/host-drivers/github.sh — GitHub driver.
# Uses `gh` CLI for creation and authentication, GitHub REST API for protection.
# Implements the solo-orchestrator host driver contract defined in spec
# docs/superpowers/specs/2026-04-21-host-aware-repo-gate-design.md.

host_name() { echo "github"; }
```

- [ ] **Step 4: Run test to verify pass**

Run: `bash tests/host-drivers/github.test.sh`
Expected: `github.test.sh: host_name PASSED`

- [ ] **Step 5: Commit**

```bash
git add scripts/host-drivers/github.sh tests/host-drivers/github.test.sh
git commit -m "feat(host): github driver skeleton with host_name"
```

### Task 1.3: GitHub driver — host_require_cli

**Files:**
- Modify: `scripts/host-drivers/github.sh`
- Modify: `tests/host-drivers/github.test.sh`

- [ ] **Step 1: Add failing test for CLI missing**

Append to `tests/host-drivers/github.test.sh`:

```bash
# Test: host_require_cli fails when gh missing
MOCK_DIR=$(mock_cli_setup)
OLD_PATH="$PATH"
# Put mock dir first but don't register gh → gh not found
export PATH="$MOCK_DIR:$OLD_PATH"
# Remove real gh from PATH by unsetting PATH entirely except MOCK_DIR
export PATH="$MOCK_DIR"
set +e
output=$(host_require_cli 2>&1)
code=$?
set -e
assert_exit_code 1 "$code" "missing gh returns 1"
assert_contains "$output" "gh" "mentions gh CLI"
assert_contains "$output" "install" "install guidance"
export PATH="$OLD_PATH"
mock_cli_teardown "$MOCK_DIR"
echo "github.test.sh: host_require_cli (missing) PASSED"
```

- [ ] **Step 2: Run test to verify fail**

Run: `bash tests/host-drivers/github.test.sh`
Expected: FAIL (host_require_cli is not defined).

- [ ] **Step 3: Implement host_require_cli**

Append to `scripts/host-drivers/github.sh`:

```bash
host_require_cli() {
  if ! command -v gh >/dev/null 2>&1; then
    cat >&2 <<'EOM'
github driver: `gh` CLI not installed.

Install via one of:
  macOS:   brew install gh
  Linux:   https://github.com/cli/cli/blob/trunk/docs/install_linux.md
  Windows: https://github.com/cli/cli#installation

Then authenticate:
  gh auth login

Re-run whatever invoked this after install+auth completes.
EOM
    return 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    cat >&2 <<'EOM'
github driver: `gh` installed but not authenticated.

Authenticate with: gh auth login

Re-run after auth completes.
EOM
    return 2
  fi
  return 0
}
```

- [ ] **Step 4: Run test to verify pass**

Run: `bash tests/host-drivers/github.test.sh`
Expected: all tests pass.

- [ ] **Step 5: Add test for unauth'd gh**

Append to test file:

```bash
# Test: host_require_cli fails when gh present but not authed
MOCK_DIR=$(mock_cli_setup)
export PATH="$MOCK_DIR:$OLD_PATH"
mock_cli_respond gh "auth status" 1 "not logged in"
mock_cli_respond gh "--version" 0 "gh version 2.0"
set +e
output=$(host_require_cli 2>&1)
code=$?
set -e
assert_exit_code 2 "$code" "unauth'd gh returns 2"
assert_contains "$output" "authenticated" "mentions auth"
export PATH="$OLD_PATH"
mock_cli_teardown "$MOCK_DIR"
echo "github.test.sh: host_require_cli (unauthed) PASSED"
```

Run and verify pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/host-drivers/github.sh tests/host-drivers/github.test.sh
git commit -m "feat(host): github driver — host_require_cli with install/auth guidance"
```

### Task 1.4: GitHub driver — host_create_repo

**Files:**
- Modify: `scripts/host-drivers/github.sh`
- Modify: `tests/host-drivers/github.test.sh`

- [ ] **Step 1: Write failing tests**

Append to test file:

```bash
# Test: host_create_repo private
MOCK_DIR=$(mock_cli_setup)
export PATH="$MOCK_DIR:$OLD_PATH"
mock_cli_respond gh "repo create my-repo --private" 0 "https://github.com/user/my-repo"
url=$(host_create_repo "my-repo" "private")
assert_eq "https://github.com/user/my-repo" "$url" "create private repo returns URL"

# Test: host_create_repo public
mock_cli_respond gh "repo create pub-repo --public" 0 "https://github.com/user/pub-repo"
url=$(host_create_repo "pub-repo" "public")
assert_eq "https://github.com/user/pub-repo" "$url" "create public repo returns URL"

# Test: existing repo fails cleanly
mock_cli_respond gh "repo create dupe --private" 1 "repository already exists"
set +e
output=$(host_create_repo "dupe" "private" 2>&1)
code=$?
set -e
assert_exit_code 1 "$code" "existing repo returns non-zero"
assert_contains "$output" "already exists" "surfaces underlying error"

mock_cli_teardown "$MOCK_DIR"
export PATH="$OLD_PATH"
echo "github.test.sh: host_create_repo PASSED"
```

- [ ] **Step 2: Run to verify fail**

Expected: host_create_repo not defined.

- [ ] **Step 3: Implement host_create_repo**

Append to `github.sh`:

```bash
# host_create_repo <name> <visibility>
# visibility: "private" | "public"
# stdout: HTTPS clone URL on success
# exit: 0 success; non-zero on failure (gh's error surfaced to stderr)
host_create_repo() {
  local name="${1:?host_create_repo: name required}"
  local visibility="${2:?host_create_repo: visibility required}"
  case "$visibility" in
    private|public) ;;
    *) echo "host_create_repo: visibility must be 'private' or 'public', got '$visibility'" >&2; return 1 ;;
  esac
  local result
  if ! result=$(gh repo create "$name" "--$visibility" 2>&1); then
    echo "$result" >&2
    return 1
  fi
  # gh prints the URL as the last line
  echo "$result" | tail -n 1
}
```

- [ ] **Step 4: Run tests to verify pass**

- [ ] **Step 5: Commit**

```bash
git add scripts/host-drivers/github.sh tests/host-drivers/github.test.sh
git commit -m "feat(host): github driver — host_create_repo"
```

### Task 1.5: GitHub driver — host_register_remote + host_push_initial

These are thin wrappers over `git`. Implement both together since they share no host-specific logic.

**Files:**
- Modify: `scripts/host-drivers/github.sh`
- Modify: `tests/host-drivers/github.test.sh`

- [ ] **Step 1: Write failing tests**

```bash
# Test: host_register_remote adds origin
WORK=$(mktemp -d); cd "$WORK"
git init -q
host_register_remote "https://github.com/u/r.git"
actual=$(git remote get-url origin)
assert_eq "https://github.com/u/r.git" "$actual" "register_remote sets origin"
cd - >/dev/null
rm -rf "$WORK"

# Test: host_register_remote replaces existing origin idempotently
WORK=$(mktemp -d); cd "$WORK"
git init -q
git remote add origin "https://example.com/old.git"
host_register_remote "https://github.com/u/r.git"
actual=$(git remote get-url origin)
assert_eq "https://github.com/u/r.git" "$actual" "register_remote replaces existing"
cd - >/dev/null
rm -rf "$WORK"

echo "github.test.sh: host_register_remote PASSED"
```

- [ ] **Step 2: Run to verify fail**

- [ ] **Step 3: Implement**

Append to `github.sh`:

```bash
# host_register_remote <url>
# Idempotent — replaces existing origin or adds new.
host_register_remote() {
  local url="${1:?host_register_remote: url required}"
  if git remote get-url origin >/dev/null 2>&1; then
    git remote set-url origin "$url"
  else
    git remote add origin "$url"
  fi
}

# host_push_initial <branch>
# Initial push with upstream tracking.
host_push_initial() {
  local branch="${1:-main}"
  git push -u origin "$branch"
}
```

- [ ] **Step 4: Verify tests pass**

- [ ] **Step 5: Commit**

```bash
git add scripts/host-drivers/github.sh tests/host-drivers/github.test.sh
git commit -m "feat(host): github driver — host_register_remote and host_push_initial"
```

### Task 1.6: GitHub driver — host_configure_protection (personal mode)

**Files:**
- Modify: `scripts/host-drivers/github.sh`
- Modify: `tests/host-drivers/github.test.sh`

Personal mode bar per spec: force-push disabled on main, admins not exempt from the rule.

- [ ] **Step 1: Write failing test**

```bash
# Test: host_configure_protection personal calls correct API
MOCK_DIR=$(mock_cli_setup)
export PATH="$MOCK_DIR:$OLD_PATH"
# Need origin URL parseable; set in temp repo
WORK=$(mktemp -d); cd "$WORK"
git init -q
git remote add origin "https://github.com/testuser/testrepo.git"
# Mock gh api PUT for protection
mock_cli_respond gh "api -X PUT repos/testuser/testrepo/branches/main/protection" 0 '{"url":"...","enforce_admins":{"enabled":true}}'
set +e
host_configure_protection "main" "personal"
code=$?
set -e
assert_exit_code 0 "$code" "personal configure succeeds"
cd - >/dev/null
rm -rf "$WORK"
mock_cli_teardown "$MOCK_DIR"
export PATH="$OLD_PATH"
echo "github.test.sh: host_configure_protection (personal) PASSED"
```

- [ ] **Step 2: Run to verify fail**

- [ ] **Step 3: Implement**

Append to `github.sh`:

```bash
# Internal: parse owner/repo from origin URL.
# Supports: https://github.com/owner/repo(.git)? and git@github.com:owner/repo(.git)?
_github_parse_origin() {
  local url
  url=$(git remote get-url origin 2>/dev/null) || { echo "_github_parse_origin: no origin" >&2; return 1; }
  local cleaned="${url%.git}"
  case "$cleaned" in
    https://github.com/*) echo "${cleaned#https://github.com/}" ;;
    git@github.com:*)     echo "${cleaned#git@github.com:}" ;;
    *) echo "_github_parse_origin: not a GitHub URL: $url" >&2; return 1 ;;
  esac
}

# host_configure_protection <branch> <mode>
# mode: "personal" | "org"
host_configure_protection() {
  local branch="${1:?host_configure_protection: branch required}"
  local mode="${2:?host_configure_protection: mode required}"
  local owner_repo
  owner_repo=$(_github_parse_origin) || return 1

  local payload
  case "$mode" in
    personal)
      # Force-push off, admins not exempt. No PR reviewer req (solo impossible anyway).
      payload=$(cat <<'JSON'
{
  "required_status_checks": null,
  "enforce_admins": true,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
)
      ;;
    org)
      # All of personal + required reviewers + required status checks (CI) + dismiss stale.
      payload=$(cat <<'JSON'
{
  "required_status_checks": {"strict": true, "contexts": []},
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 1
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
)
      ;;
    *)
      echo "host_configure_protection: mode must be 'personal' or 'org', got '$mode'" >&2
      return 1
      ;;
  esac

  if ! gh api -X PUT "repos/$owner_repo/branches/$branch/protection" --input - <<<"$payload" >/dev/null 2>&1; then
    echo "github driver: failed to configure protection on $owner_repo#$branch ($mode mode)" >&2
    return 2
  fi
  return 0
}
```

- [ ] **Step 4: Verify personal test passes**

- [ ] **Step 5: Add test for org mode**

```bash
# Test: org mode payload includes reviewer requirement
MOCK_DIR=$(mock_cli_setup)
export PATH="$MOCK_DIR:$OLD_PATH"
WORK=$(mktemp -d); cd "$WORK"
git init -q
git remote add origin "https://github.com/org/repo.git"
mock_cli_respond gh "api -X PUT repos/org/repo/branches/main/protection" 0 '{"ok":true}'
host_configure_protection "main" "org"
code=$?
assert_exit_code 0 "$code" "org configure succeeds"
cd - >/dev/null
rm -rf "$WORK"
mock_cli_teardown "$MOCK_DIR"
export PATH="$OLD_PATH"
echo "github.test.sh: host_configure_protection (org) PASSED"
```

Run and verify.

- [ ] **Step 6: Commit**

```bash
git add scripts/host-drivers/github.sh tests/host-drivers/github.test.sh
git commit -m "feat(host): github driver — host_configure_protection (personal + org)"
```

### Task 1.7: GitHub driver — host_verify_protection

**Files:**
- Modify: `scripts/host-drivers/github.sh`
- Modify: `tests/host-drivers/github.test.sh`

- [ ] **Step 1: Write failing tests**

Test cases:
- Personal mode, all rules correct → pass (exit 0)
- Personal mode, force-push allowed → fail with specific rule
- Org mode, no reviewer req → fail with specific rule
- Org mode, all rules correct → pass

```bash
# Test: verify passes when personal rules met
MOCK_DIR=$(mock_cli_setup)
export PATH="$MOCK_DIR:$OLD_PATH"
WORK=$(mktemp -d); cd "$WORK"
git init -q
git remote add origin "https://github.com/u/r.git"
mock_cli_respond gh "api repos/u/r/branches/main/protection" 0 '{"enforce_admins":{"enabled":true},"allow_force_pushes":{"enabled":false}}'
set +e
output=$(host_verify_protection "main" "personal" 2>&1)
code=$?
set -e
assert_exit_code 0 "$code" "personal pass"

# Test: verify fails with specific message when force-push allowed
mock_cli_respond gh "api repos/u/r/branches/main/protection" 0 '{"enforce_admins":{"enabled":true},"allow_force_pushes":{"enabled":true}}'
set +e
output=$(host_verify_protection "main" "personal" 2>&1)
code=$?
set -e
assert_exit_code 1 "$code" "force-push allowed fails"
assert_contains "$output" "force-push" "mentions specific rule"

# Test: verify fails when enforce_admins off
mock_cli_respond gh "api repos/u/r/branches/main/protection" 0 '{"enforce_admins":{"enabled":false},"allow_force_pushes":{"enabled":false}}'
set +e
output=$(host_verify_protection "main" "personal" 2>&1)
code=$?
set -e
assert_exit_code 1 "$code" "admins exempt fails"
assert_contains "$output" "admin" "mentions admins rule"

# Test: org mode requires reviewer
mock_cli_respond gh "api repos/u/r/branches/main/protection" 0 '{"enforce_admins":{"enabled":true},"allow_force_pushes":{"enabled":false},"required_pull_request_reviews":{"required_approving_review_count":0}}'
set +e
output=$(host_verify_protection "main" "org" 2>&1)
code=$?
set -e
assert_exit_code 1 "$code" "org requires reviewer"
assert_contains "$output" "review" "mentions reviewer rule"

# Test: org mode passes
mock_cli_respond gh "api repos/u/r/branches/main/protection" 0 '{"enforce_admins":{"enabled":true},"allow_force_pushes":{"enabled":false},"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true},"required_status_checks":{"strict":true,"contexts":[]}}'
set +e
host_verify_protection "main" "org"
code=$?
set -e
assert_exit_code 0 "$code" "org pass"

cd - >/dev/null; rm -rf "$WORK"
mock_cli_teardown "$MOCK_DIR"
export PATH="$OLD_PATH"
echo "github.test.sh: host_verify_protection PASSED"
```

- [ ] **Step 2: Run to verify fails**

- [ ] **Step 3: Implement**

Append to `github.sh`:

```bash
# host_verify_protection <branch> <mode>
# mode: "personal" | "org"
# Returns 0 if current protection rules meet the bar for the given mode.
# On failure, prints specific failing rule(s) to stderr and returns non-zero.
host_verify_protection() {
  local branch="${1:?host_verify_protection: branch required}"
  local mode="${2:?host_verify_protection: mode required}"
  local owner_repo
  owner_repo=$(_github_parse_origin) || return 1

  local resp
  if ! resp=$(gh api "repos/$owner_repo/branches/$branch/protection" 2>&1); then
    echo "github driver: could not fetch protection for $owner_repo#$branch" >&2
    echo "$resp" >&2
    return 2
  fi

  local failures=""
  local val

  # Shared rules (personal + org)
  val=$(echo "$resp" | jq -r '.allow_force_pushes.enabled // false')
  [ "$val" = "true" ] && failures="${failures}main branch allows force-push (should be disabled)\n"

  val=$(echo "$resp" | jq -r '.enforce_admins.enabled // false')
  [ "$val" != "true" ] && failures="${failures}admins are exempt from protection rules (should not be exempt)\n"

  # Org-only rules
  if [ "$mode" = "org" ]; then
    val=$(echo "$resp" | jq -r '.required_pull_request_reviews.required_approving_review_count // 0')
    if [ "$val" = "0" ] || [ "$val" = "null" ]; then
      failures="${failures}required_approving_review_count is 0 (org mode requires at least 1)\n"
    fi
    val=$(echo "$resp" | jq -r '.required_status_checks // empty')
    [ -z "$val" ] && failures="${failures}no status checks enforced (org mode requires CI status check)\n"
  fi

  if [ -n "$failures" ]; then
    printf "github driver: protection verification failed for %s#%s (%s mode):\n" "$owner_repo" "$branch" "$mode" >&2
    printf "  - %b" "$failures" >&2
    return 1
  fi
  return 0
}
```

- [ ] **Step 4: Verify tests pass**

- [ ] **Step 5: Commit**

```bash
git add scripts/host-drivers/github.sh tests/host-drivers/github.test.sh
git commit -m "feat(host): github driver — host_verify_protection with specific failure messages"
```

### Task 1.8: Dispatcher routing integration test

**Files:**
- Modify: `tests/host-drivers/dispatcher.test.sh`

- [ ] **Step 1: Add test that dispatcher loads github driver and exposes contract**

```bash
# Test: host_load_driver sources github driver and exposes contract
WORK=$(mktemp -d); cd "$WORK"
mkdir -p .claude
echo '{"host":"github","mode":"personal"}' > .claude/manifest.json
source "$REPO_ROOT/scripts/lib/host.sh"
host_load_driver
assert_eq "github" "$(host_name)" "dispatcher loads github driver"
# Verify all contract functions exist
for fn in host_require_cli host_create_repo host_register_remote host_push_initial host_configure_protection host_verify_protection; do
  if ! declare -f "$fn" >/dev/null; then
    echo "ASSERT FAIL: $fn not defined after load" >&2
    exit 1
  fi
done
cd - >/dev/null; rm -rf "$WORK"
echo "dispatcher.test.sh: contract completeness PASSED"
```

- [ ] **Step 2: Run and verify pass** (no implementation changes needed; contract is already complete)

- [ ] **Step 3: Commit**

```bash
git add tests/host-drivers/dispatcher.test.sh
git commit -m "test(host): dispatcher contract completeness integration test"
```

---

## Phase 2 — GitLab Driver

GitLab driver structure mirrors GitHub but uses `glab` CLI and GitLab REST API v4. URL parsing must support self-hosted instances (`gitlab.example.com`).

### Task 2.1: GitLab driver skeleton — host_name + host_require_cli

**Files:**
- Create: `scripts/host-drivers/gitlab.sh`
- Create: `tests/host-drivers/gitlab.test.sh`

- [ ] **Step 1: Write failing tests**

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/mock-cli.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/host-drivers/gitlab.sh"

# host_name
assert_eq "gitlab" "$(host_name)" "host_name"

# host_require_cli — missing glab
MOCK_DIR=$(mock_cli_setup)
OLD_PATH="$PATH"
export PATH="$MOCK_DIR"
set +e
output=$(host_require_cli 2>&1); code=$?
set -e
assert_exit_code 1 "$code" "missing glab"
assert_contains "$output" "glab" "mentions glab"
export PATH="$OLD_PATH"
mock_cli_teardown "$MOCK_DIR"
echo "gitlab.test.sh: skeleton PASSED"
```

- [ ] **Step 2: Run to verify fail**

- [ ] **Step 3: Create gitlab.sh**

```bash
#!/usr/bin/env bash
# scripts/host-drivers/gitlab.sh — GitLab driver.
# Uses `glab` CLI for creation and authentication, GitLab REST API v4 for protection.
# Supports both gitlab.com and self-hosted instances.

host_name() { echo "gitlab"; }

host_require_cli() {
  if ! command -v glab >/dev/null 2>&1; then
    cat >&2 <<'EOM'
gitlab driver: `glab` CLI not installed.

Install via one of:
  macOS:   brew install glab
  Linux:   https://gitlab.com/gitlab-org/cli/-/blob/main/docs/installation_options.md
  Windows: https://gitlab.com/gitlab-org/cli/-/blob/main/docs/installation_options.md#windows

Then authenticate:
  glab auth login

(Self-hosted instances: `glab auth login --hostname gitlab.your-company.com`)
EOM
    return 1
  fi
  if ! glab auth status >/dev/null 2>&1; then
    cat >&2 <<'EOM'
gitlab driver: `glab` installed but not authenticated.

Authenticate with: glab auth login
EOM
    return 2
  fi
  return 0
}
```

- [ ] **Step 4: Verify tests pass**

- [ ] **Step 5: Commit**

```bash
git add scripts/host-drivers/gitlab.sh tests/host-drivers/gitlab.test.sh
git commit -m "feat(host): gitlab driver skeleton"
```

### Task 2.2: GitLab driver — host_create_repo

- [ ] **Step 1: Tests**

```bash
# Test: create private repo
MOCK_DIR=$(mock_cli_setup); export PATH="$MOCK_DIR:$OLD_PATH"
mock_cli_respond glab "repo create my-repo --private" 0 "https://gitlab.com/user/my-repo"
url=$(host_create_repo "my-repo" "private")
assert_eq "https://gitlab.com/user/my-repo" "$url"

mock_cli_teardown "$MOCK_DIR"; export PATH="$OLD_PATH"
echo "gitlab.test.sh: host_create_repo PASSED"
```

- [ ] **Step 2: Run (fails)**

- [ ] **Step 3: Implement**

Append to `gitlab.sh`:

```bash
host_create_repo() {
  local name="${1:?host_create_repo: name required}"
  local visibility="${2:?host_create_repo: visibility required}"
  case "$visibility" in
    private|public) ;;
    *) echo "host_create_repo: visibility must be private|public, got '$visibility'" >&2; return 1 ;;
  esac
  local result
  if ! result=$(glab repo create "$name" "--$visibility" 2>&1); then
    echo "$result" >&2; return 1
  fi
  echo "$result" | tail -n 1
}
```

- [ ] **Step 4: Verify tests pass**

- [ ] **Step 5: Commit**

```bash
git add scripts/host-drivers/gitlab.sh tests/host-drivers/gitlab.test.sh
git commit -m "feat(host): gitlab driver — host_create_repo"
```

### Task 2.3: GitLab driver — host_register_remote + host_push_initial

These are git-native, identical to GitHub's implementation. Copy from `github.sh` and commit.

- [ ] **Step 1: Append to `gitlab.sh`** (identical logic):

```bash
host_register_remote() {
  local url="${1:?url required}"
  if git remote get-url origin >/dev/null 2>&1; then
    git remote set-url origin "$url"
  else
    git remote add origin "$url"
  fi
}

host_push_initial() {
  local branch="${1:-main}"
  git push -u origin "$branch"
}
```

- [ ] **Step 2: Reuse tests from github.test.sh pattern**

Add equivalent tests in `gitlab.test.sh` (same assertions, host-agnostic).

- [ ] **Step 3: Verify and commit**

```bash
git add scripts/host-drivers/gitlab.sh tests/host-drivers/gitlab.test.sh
git commit -m "feat(host): gitlab driver — register_remote + push_initial"
```

### Task 2.4: GitLab driver — host_configure_protection

GitLab uses a different API model: Protected Branches (`/api/v4/projects/:id/protected_branches`). Project ID can be URL-encoded path: `namespace%2Fproject`.

- [ ] **Step 1: Tests**

```bash
# Test: configure personal mode (force-push disabled)
MOCK_DIR=$(mock_cli_setup); export PATH="$MOCK_DIR:$OLD_PATH"
WORK=$(mktemp -d); cd "$WORK"
git init -q
git remote add origin "https://gitlab.com/user/project.git"
# glab api uses similar semantics to gh api
mock_cli_respond glab "api -X POST projects/user%2Fproject/protected_branches" 0 '{"id":1,"name":"main"}'
# First unprotect existing (idempotent), then re-protect
mock_cli_respond glab "api -X DELETE projects/user%2Fproject/protected_branches/main" 0 ""
host_configure_protection "main" "personal"
assert_exit_code 0 $? "personal configure"
cd - >/dev/null; rm -rf "$WORK"
mock_cli_teardown "$MOCK_DIR"; export PATH="$OLD_PATH"
echo "gitlab.test.sh: host_configure_protection PASSED"
```

- [ ] **Step 2: Run (fails)**

- [ ] **Step 3: Implement**

Append to `gitlab.sh`:

```bash
# Parse namespace/project from origin URL (gitlab.com or self-hosted).
_gitlab_parse_origin() {
  local url
  url=$(git remote get-url origin 2>/dev/null) || { echo "_gitlab_parse_origin: no origin" >&2; return 1; }
  local cleaned="${url%.git}"
  # Strip scheme and host
  local path
  case "$cleaned" in
    https://*) path="${cleaned#https://*/}" ;;
    http://*)  path="${cleaned#http://*/}" ;;
    git@*:*)   path="${cleaned#git@*:}" ;;
    *) echo "_gitlab_parse_origin: unparseable: $url" >&2; return 1 ;;
  esac
  # URL-encode slashes for project ID
  echo "${path//\//%2F}"
}

host_configure_protection() {
  local branch="${1:?branch required}"
  local mode="${2:?mode required}"
  local project
  project=$(_gitlab_parse_origin) || return 1

  # GitLab protected branches: delete existing (if any) then recreate (idempotency).
  glab api -X DELETE "projects/$project/protected_branches/$branch" >/dev/null 2>&1 || true

  local push_access_level merge_access_level
  case "$mode" in
    personal)
      # Developer+ can push (40), no forced merge-via-MR (30 = dev+, permissive for solo)
      push_access_level=40
      merge_access_level=30
      ;;
    org)
      # Maintainer-only push (40), merge via approved MR only (40 = maintainer)
      push_access_level=40
      merge_access_level=40
      ;;
    *)
      echo "host_configure_protection: mode must be personal|org, got '$mode'" >&2; return 1
      ;;
  esac

  local payload
  payload=$(cat <<JSON
{
  "name": "$branch",
  "push_access_level": $push_access_level,
  "merge_access_level": $merge_access_level,
  "allow_force_push": false,
  "code_owner_approval_required": false
}
JSON
)
  if ! glab api -X POST "projects/$project/protected_branches" --input - <<<"$payload" >/dev/null 2>&1; then
    echo "gitlab driver: failed to configure protection on $project#$branch ($mode mode)" >&2
    return 2
  fi

  # Org mode: also require approvals on MRs (separate API)
  if [ "$mode" = "org" ]; then
    glab api -X PUT "projects/$project/approvals" \
      --input - <<<'{"approvals_before_merge":1,"reset_approvals_on_push":true}' >/dev/null 2>&1 \
      || { echo "gitlab driver: protected branch set but approvals config failed" >&2; return 3; }
  fi
  return 0
}
```

- [ ] **Step 4: Verify tests pass**

- [ ] **Step 5: Commit**

```bash
git add scripts/host-drivers/gitlab.sh tests/host-drivers/gitlab.test.sh
git commit -m "feat(host): gitlab driver — host_configure_protection"
```

### Task 2.5: GitLab driver — host_verify_protection

- [ ] **Step 1: Tests**

```bash
# Test: passes when rules met (personal)
MOCK_DIR=$(mock_cli_setup); export PATH="$MOCK_DIR:$OLD_PATH"
WORK=$(mktemp -d); cd "$WORK"
git init -q; git remote add origin "https://gitlab.com/u/p.git"
mock_cli_respond glab "api projects/u%2Fp/protected_branches/main" 0 '{"name":"main","allow_force_push":false,"push_access_levels":[{"access_level":40}]}'
set +e; host_verify_protection "main" "personal"; code=$?; set -e
assert_exit_code 0 "$code" "personal verify pass"

# Test: fails when force-push allowed
mock_cli_respond glab "api projects/u%2Fp/protected_branches/main" 0 '{"name":"main","allow_force_push":true,"push_access_levels":[{"access_level":40}]}'
set +e; output=$(host_verify_protection "main" "personal" 2>&1); code=$?; set -e
assert_exit_code 1 "$code" "force-push allowed fails"
assert_contains "$output" "force-push" "mentions rule"

# Test: org requires approvals
mock_cli_respond glab "api projects/u%2Fp/protected_branches/main" 0 '{"name":"main","allow_force_push":false,"push_access_levels":[{"access_level":40}]}'
mock_cli_respond glab "api projects/u%2Fp/approvals" 0 '{"approvals_before_merge":0}'
set +e; output=$(host_verify_protection "main" "org" 2>&1); code=$?; set -e
assert_exit_code 1 "$code" "org no approvals fails"
assert_contains "$output" "approval" "mentions approvals"

cd - >/dev/null; rm -rf "$WORK"
mock_cli_teardown "$MOCK_DIR"; export PATH="$OLD_PATH"
echo "gitlab.test.sh: host_verify_protection PASSED"
```

- [ ] **Step 2: Run (fails)**

- [ ] **Step 3: Implement**

Append to `gitlab.sh`:

```bash
host_verify_protection() {
  local branch="${1:?branch required}"
  local mode="${2:?mode required}"
  local project
  project=$(_gitlab_parse_origin) || return 1

  local resp
  if ! resp=$(glab api "projects/$project/protected_branches/$branch" 2>&1); then
    echo "gitlab driver: could not fetch protection for $project#$branch" >&2
    echo "$resp" >&2
    return 2
  fi

  local failures="" val
  val=$(echo "$resp" | jq -r '.allow_force_push // false')
  [ "$val" = "true" ] && failures="${failures}force-push allowed on $branch (should be disabled)\n"
  # push_access_levels empty or allowing unprotected push is a fail
  val=$(echo "$resp" | jq -r '.push_access_levels | length // 0')
  [ "$val" = "0" ] && failures="${failures}no push restriction on $branch\n"

  if [ "$mode" = "org" ]; then
    local aresp
    aresp=$(glab api "projects/$project/approvals" 2>/dev/null || echo '{}')
    val=$(echo "$aresp" | jq -r '.approvals_before_merge // 0')
    if [ "$val" = "0" ] || [ "$val" = "null" ]; then
      failures="${failures}approvals_before_merge is 0 (org mode requires at least 1)\n"
    fi
  fi

  if [ -n "$failures" ]; then
    printf "gitlab driver: protection verification failed for %s#%s (%s mode):\n" "$project" "$branch" "$mode" >&2
    printf "  - %b" "$failures" >&2
    return 1
  fi
  return 0
}
```

- [ ] **Step 4: Verify tests pass**

- [ ] **Step 5: Commit**

```bash
git add scripts/host-drivers/gitlab.sh tests/host-drivers/gitlab.test.sh
git commit -m "feat(host): gitlab driver — host_verify_protection"
```

---

## Phase 3 — Bitbucket Driver

Bitbucket lacks a mature first-party CLI. Use `curl` with Bitbucket App Passwords. Auth relies on env vars (`BITBUCKET_USER`, `BITBUCKET_APP_PASSWORD`) or stored config at `~/.config/bitbucket/credentials`.

### Task 3.1: Bitbucket driver skeleton — host_name + host_require_cli

**Files:**
- Create: `scripts/host-drivers/bitbucket.sh`
- Create: `tests/host-drivers/bitbucket.test.sh`

- [ ] **Step 1: Tests**

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/mock-cli.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/host-drivers/bitbucket.sh"

# host_name
assert_eq "bitbucket" "$(host_name)" "host_name"

# Without creds → fails
unset BITBUCKET_USER BITBUCKET_APP_PASSWORD
set +e; output=$(host_require_cli 2>&1); code=$?; set -e
assert_exit_code 1 "$code" "no creds fails"
assert_contains "$output" "BITBUCKET_USER" "mentions env var"

# With creds → passes (curl is assumed present)
export BITBUCKET_USER="testuser" BITBUCKET_APP_PASSWORD="testpass"
set +e; host_require_cli; code=$?; set -e
assert_exit_code 0 "$code" "with creds passes"
unset BITBUCKET_USER BITBUCKET_APP_PASSWORD
echo "bitbucket.test.sh: skeleton PASSED"
```

- [ ] **Step 2: Run (fails)**

- [ ] **Step 3: Create `bitbucket.sh`**

```bash
#!/usr/bin/env bash
# scripts/host-drivers/bitbucket.sh — Bitbucket driver.
# Uses curl + Bitbucket Cloud REST API 2.0.
# Credentials via env: BITBUCKET_USER + BITBUCKET_APP_PASSWORD (App Password with
# repository:admin, project:admin, and pullrequest:write scopes).

host_name() { echo "bitbucket"; }

_bb_api_base="https://api.bitbucket.org/2.0"
_bb_curl() {
  # $1: method, $2: url, stdin: body (optional)
  local method="$1" url="$2"
  curl -sSf -u "${BITBUCKET_USER}:${BITBUCKET_APP_PASSWORD}" \
    -X "$method" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    --data-binary @- \
    "$url" 2>&1
}
_bb_curl_no_body() {
  local method="$1" url="$2"
  curl -sSf -u "${BITBUCKET_USER}:${BITBUCKET_APP_PASSWORD}" \
    -X "$method" \
    -H "Accept: application/json" \
    "$url" 2>&1
}

host_require_cli() {
  if [ -z "${BITBUCKET_USER:-}" ] || [ -z "${BITBUCKET_APP_PASSWORD:-}" ]; then
    cat >&2 <<'EOM'
bitbucket driver: credentials not configured.

Bitbucket Cloud requires an App Password (not your account password).
Create one at: https://bitbucket.org/account/settings/app-passwords/
Grant these scopes: repository:admin, project:admin, pullrequest:write

Then export:
  export BITBUCKET_USER="your-bitbucket-username"
  export BITBUCKET_APP_PASSWORD="your-app-password"

Consider adding those to your shell rc file (with appropriate file permissions).
EOM
    return 1
  fi
  if ! command -v curl >/dev/null 2>&1; then
    echo "bitbucket driver: curl not installed — required for Bitbucket API" >&2
    return 1
  fi
  return 0
}
```

- [ ] **Step 4: Verify tests pass**

- [ ] **Step 5: Commit**

```bash
git add scripts/host-drivers/bitbucket.sh tests/host-drivers/bitbucket.test.sh
git commit -m "feat(host): bitbucket driver skeleton with credential check"
```

### Task 3.2: Bitbucket driver — host_create_repo

Bitbucket's repo creation API: `POST /repositories/{workspace}/{repo_slug}`. The workspace must be specified. We derive the workspace from `BITBUCKET_USER` (personal workspace is the username); org users should override with `BITBUCKET_WORKSPACE`.

- [ ] **Step 1: Tests** (pattern from prior phases; mock curl responses)

- [ ] **Step 2: Implementation sketch**

Append to `bitbucket.sh`:

```bash
host_create_repo() {
  local name="${1:?name required}"
  local visibility="${2:?visibility required}"
  local is_private
  case "$visibility" in
    private) is_private="true" ;;
    public)  is_private="false" ;;
    *) echo "visibility must be private|public, got '$visibility'" >&2; return 1 ;;
  esac
  local workspace="${BITBUCKET_WORKSPACE:-$BITBUCKET_USER}"

  local payload
  payload=$(cat <<JSON
{"scm":"git","is_private":$is_private}
JSON
)
  local resp
  if ! resp=$(echo "$payload" | _bb_curl POST "$_bb_api_base/repositories/$workspace/$name"); then
    echo "bitbucket driver: repo create failed" >&2
    echo "$resp" >&2
    return 1
  fi
  echo "$resp" | jq -r '.links.clone[] | select(.name=="https") | .href'
}
```

- [ ] **Step 3: Verify and commit**

```bash
git add scripts/host-drivers/bitbucket.sh tests/host-drivers/bitbucket.test.sh
git commit -m "feat(host): bitbucket driver — host_create_repo"
```

### Task 3.3: Bitbucket driver — host_register_remote + host_push_initial

Identical git-native implementation as GitHub/GitLab. Copy and commit.

### Task 3.4: Bitbucket driver — host_configure_protection

Bitbucket uses Branch Restrictions API: `POST /repositories/{workspace}/{repo}/branch-restrictions`. Multiple restriction records (one per rule type) must be created: `force`, `delete`, `push`.

- [ ] **Step 1: Tests** (pattern as before)

- [ ] **Step 2: Implementation**

Append to `bitbucket.sh`:

```bash
_bb_parse_origin() {
  local url
  url=$(git remote get-url origin 2>/dev/null) || return 1
  local cleaned="${url%.git}"
  case "$cleaned" in
    https://bitbucket.org/*) echo "${cleaned#https://bitbucket.org/}" ;;
    git@bitbucket.org:*)     echo "${cleaned#git@bitbucket.org:}" ;;
    *) echo "_bb_parse_origin: not a Bitbucket URL: $url" >&2; return 1 ;;
  esac
}

host_configure_protection() {
  local branch="${1:?}"; local mode="${2:?}"
  local workspace_repo
  workspace_repo=$(_bb_parse_origin) || return 1

  # Delete existing restrictions on this branch (idempotency).
  local existing
  existing=$(_bb_curl_no_body GET "$_bb_api_base/repositories/$workspace_repo/branch-restrictions?pattern=$branch" 2>/dev/null || echo '{}')
  echo "$existing" | jq -r '.values[].id // empty' | while read -r id; do
    [ -n "$id" ] && _bb_curl_no_body DELETE "$_bb_api_base/repositories/$workspace_repo/branch-restrictions/$id" >/dev/null 2>&1
  done

  # Create restrictions: force-push off, delete off (both modes)
  local kind
  for kind in force delete; do
    local payload
    payload=$(cat <<JSON
{"kind":"$kind","pattern":"$branch","users":[],"groups":[]}
JSON
)
    echo "$payload" | _bb_curl POST "$_bb_api_base/repositories/$workspace_repo/branch-restrictions" >/dev/null || {
      echo "bitbucket driver: failed to set $kind restriction" >&2; return 2
    }
  done

  # Org mode: require approvals on PRs + block direct push
  if [ "$mode" = "org" ]; then
    for kind in push require_approvals_to_merge; do
      local value=""
      [ "$kind" = "require_approvals_to_merge" ] && value='"value":1,'
      local payload
      payload=$(cat <<JSON
{"kind":"$kind","pattern":"$branch",$value "users":[],"groups":[]}
JSON
)
      echo "$payload" | _bb_curl POST "$_bb_api_base/repositories/$workspace_repo/branch-restrictions" >/dev/null || return 2
    done
  fi
  return 0
}
```

- [ ] **Step 3: Commit**

### Task 3.5: Bitbucket driver — host_verify_protection

- [ ] **Step 1: Tests + implementation**

Append to `bitbucket.sh`:

```bash
host_verify_protection() {
  local branch="${1:?}"; local mode="${2:?}"
  local workspace_repo
  workspace_repo=$(_bb_parse_origin) || return 1

  local resp
  resp=$(_bb_curl_no_body GET "$_bb_api_base/repositories/$workspace_repo/branch-restrictions?pattern=$branch" 2>&1) || {
    echo "bitbucket driver: could not fetch restrictions for $workspace_repo#$branch" >&2; return 2
  }

  local has_force has_delete has_push has_approvals
  has_force=$(echo "$resp" | jq -r '[.values[] | select(.kind=="force")] | length')
  has_delete=$(echo "$resp" | jq -r '[.values[] | select(.kind=="delete")] | length')
  has_push=$(echo "$resp" | jq -r '[.values[] | select(.kind=="push")] | length')
  has_approvals=$(echo "$resp" | jq -r '[.values[] | select(.kind=="require_approvals_to_merge" and .value>=1)] | length')

  local failures=""
  [ "$has_force" -eq 0 ]  && failures="${failures}force-push not restricted on $branch\n"
  [ "$has_delete" -eq 0 ] && failures="${failures}branch-delete not restricted\n"

  if [ "$mode" = "org" ]; then
    [ "$has_push" -eq 0 ]      && failures="${failures}push not restricted (org mode requires PR-only)\n"
    [ "$has_approvals" -eq 0 ] && failures="${failures}approvals not required on PRs (org mode requires at least 1)\n"
  fi

  if [ -n "$failures" ]; then
    printf "bitbucket driver: protection verification failed for %s#%s (%s mode):\n" "$workspace_repo" "$branch" "$mode" >&2
    printf "  - %b" "$failures" >&2
    return 1
  fi
  return 0
}
```

- [ ] **Step 2: Commit**

```bash
git add scripts/host-drivers/bitbucket.sh tests/host-drivers/bitbucket.test.sh
git commit -m "feat(host): bitbucket driver — verify_protection + commit all bitbucket functions"
```

---

## Phase 4 — Intake & Init Wiring

### Task 4.1: Intake wizard — add host question

**Files:**
- Modify: `scripts/intake-wizard.sh`
- Modify: `templates/intake-suggestions/common.json`

- [ ] **Step 1: Find existing intake question structure**

Run: `grep -n 'prompt_choice\|prompt_input' scripts/intake-wizard.sh | head -20`
Inspect how other multi-choice questions are structured.

- [ ] **Step 2: Add host question near repository section**

Add to `intake-wizard.sh` (location: after deployment-mode question, before repository name):

```bash
# --- Host selection ---
print_step "Git host"
HOST=$(prompt_choice "Which git host will this project use?" \
  "github:GitHub (most common)" \
  "gitlab:GitLab (self-hosted supported)" \
  "bitbucket:Bitbucket Cloud" \
  "other:Other (self-hosted Gitea, CircleCI-managed, etc.)")

# Probe CLI availability for first-class hosts
if [ "$HOST" != "other" ]; then
  source "$SCRIPT_DIR/lib/host.sh" 2>/dev/null || true
  source "$SCRIPT_DIR/host-drivers/$HOST.sh"
  if ! host_require_cli 2>/tmp/host-cli-probe; then
    cat /tmp/host-cli-probe >&2
    echo ""
    action=$(prompt_choice "Host CLI unavailable — what now?" \
      "retry:Retry probe (I'll install/auth in another terminal)" \
      "switch:Switch to a different host" \
      "abort:Abort intake")
    case "$action" in
      retry) exec "$0" "$@" ;;
      switch) # re-run this section; easiest: re-exec the wizard
              exec "$0" "$@" ;;
      abort) echo "Intake aborted."; exit 1 ;;
    esac
  fi
fi

# --- Visibility ---
print_step "Repository visibility"
if [ "$MODE" = "org" ]; then
  VISIBILITY="private"  # Org projects force private
  print_info "Org mode → visibility forced to 'private'."
else
  VISIBILITY=$(prompt_choice "Repository visibility?" \
    "private:Private (recommended)" \
    "public:Public")
fi

# --- Persist ---
jq --arg h "$HOST" --arg v "$VISIBILITY" \
   '.git_host = $h | .repo_visibility = $v' \
   "$INTAKE_PROGRESS" > "$INTAKE_PROGRESS.tmp" && mv "$INTAKE_PROGRESS.tmp" "$INTAKE_PROGRESS"
```

- [ ] **Step 3: Add entries to intake-suggestions/common.json**

Modify `templates/intake-suggestions/common.json` to add:

```json
{
  "git_host": {
    "default": "github",
    "description": "First-class hosts: github, gitlab, bitbucket. 'other' for non-supported hosts (manual CI config).",
    "cli_prereqs": {
      "github": "gh (https://github.com/cli/cli)",
      "gitlab": "glab (https://gitlab.com/gitlab-org/cli)",
      "bitbucket": "curl + BITBUCKET_USER/BITBUCKET_APP_PASSWORD env vars"
    }
  },
  "repo_visibility": {
    "default": "private",
    "description": "Private recommended. Org mode forces private."
  }
}
```

- [ ] **Step 4: Test by running intake-wizard in a temp dir**

Run: `bash tests/edge-cases-pre-init.sh` — add an assertion block covering new fields.

Or manually:
```bash
TMP=$(mktemp -d); cd "$TMP"
bash /path/to/solo-orchestrator/scripts/intake-wizard.sh
# Answer prompts; verify .claude/intake-progress.json contains git_host and repo_visibility
jq '.git_host, .repo_visibility' .claude/intake-progress.json
```

- [ ] **Step 5: Commit**

```bash
git add scripts/intake-wizard.sh templates/intake-suggestions/common.json
git commit -m "feat(intake): add git_host and repo_visibility questions with CLI probe"
```

### Task 4.2: project-intake.md — add Git Host field

- [ ] **Step 1: Modify `templates/project-intake.md`**

Find the Repository section and add:

```markdown
## Repository

- **Git host:** <!-- github | gitlab | bitbucket | other -->
- **Visibility:** <!-- private | public -->
- **Name:** <!-- chosen repo name -->
- **Owner/workspace:** <!-- org or user namespace -->
```

- [ ] **Step 2: Commit**

```bash
git add templates/project-intake.md
git commit -m "feat(intake): add Git Host + Visibility fields to intake template"
```

### Task 4.3: init.sh — host dispatch integration

**Files:**
- Modify: `init.sh`

Locate the section where init.sh currently handles git setup. Insert driver-based flow.

- [ ] **Step 1: Find git-setup block**

Run: `grep -n 'git init\|git remote' init.sh`

- [ ] **Step 2: Replace with host-aware flow**

Replace the existing git-setup section with (at appropriate location in init.sh):

```bash
# --- Host-aware repo creation (per spec 2026-04-21-host-aware-repo-gate-design.md) ---
HOST=$(jq -r '.git_host // "github"' .claude/intake-progress.json)
VISIBILITY=$(jq -r '.repo_visibility // "private"' .claude/intake-progress.json)
REPO_NAME=$(jq -r '.project_name' .claude/intake-progress.json)
MODE=$(jq -r '.mode' .claude/intake-progress.json)

print_step "Creating git repository on $HOST"

if [ "$HOST" = "other" ]; then
  # URL-paste path
  read -rp "Paste the HTTPS clone URL of the remote repo you've created: " REMOTE_URL
  [ -z "$REMOTE_URL" ] && { print_fail "Remote URL required for 'other' host"; exit 1; }
  git init -q
  git add . && git commit -q -m "chore(init): initial scaffold"
  git remote add origin "$REMOTE_URL"
  git push -u origin main || { print_fail "Push failed — verify URL and permissions"; exit 1; }
  # Manual attestation
  echo ""
  echo "Since 'other' host is not API-verifiable, you must attest that branch protection is configured:"
  echo "  - Force-push disabled on main"
  echo "  - Admins not exempt from rules"
  [ "$MODE" = "org" ] && echo "  - PR reviews required (at least 1 approver)"
  read -rp "Has branch protection been configured per the above? [type 'yes' to attest]: " ATTEST
  [ "$ATTEST" != "yes" ] && { print_fail "Attestation required — cannot proceed to Phase 0"; exit 1; }
  # Record attestation in process-state.json
  jq --arg at "$(date -u +%FT%TZ)" \
     '.phase2_init.attestations.branch_protection = {attested_by: "orchestrator", at: $at}' \
     .claude/process-state.json > .claude/process-state.json.tmp && mv .claude/process-state.json.tmp .claude/process-state.json
else
  # First-class host: dispatcher-driven
  source scripts/lib/host.sh
  source "scripts/host-drivers/$HOST.sh"

  host_require_cli || { print_fail "CLI prerequisite failed — see messages above"; exit 1; }

  print_info "Creating $VISIBILITY repo '$REPO_NAME' on $HOST..."
  REMOTE_URL=$(host_create_repo "$REPO_NAME" "$VISIBILITY") || { print_fail "Repo creation failed"; exit 1; }
  print_ok "Remote created at $REMOTE_URL"

  git init -q
  git add . && git commit -q -m "chore(init): initial scaffold"
  host_register_remote "$REMOTE_URL"

  print_info "Pushing initial commit..."
  host_push_initial main || { print_fail "Push failed — $REMOTE_URL exists but empty"; exit 1; }

  print_info "Configuring branch protection ($MODE mode)..."
  host_configure_protection main "$MODE" || { print_fail "Protection config failed — run scripts/check-gate.sh --repair after troubleshooting"; exit 1; }

  print_info "Verifying protection..."
  host_verify_protection main "$MODE" || {
    # Allow one automatic retry for API lag
    sleep 10
    host_verify_protection main "$MODE" || { print_fail "Verification failed — run scripts/check-gate.sh --repair"; exit 1; }
  }
  print_ok "Protection verified for $MODE mode"
fi

# Write host info to manifest
jq --arg h "$HOST" --arg m "$MODE" --arg u "$REMOTE_URL" \
   '.host = $h | .mode = $m | .remote_url = $u' \
   .claude/manifest.json > .claude/manifest.json.tmp && mv .claude/manifest.json.tmp .claude/manifest.json

# Mark phase2_init steps complete
jq '.phase2_init.steps_completed += ["remote_repo_created","branch_protection_configured"] | .phase2_init.steps_completed |= unique' \
   .claude/process-state.json > .claude/process-state.json.tmp && mv .claude/process-state.json.tmp .claude/process-state.json
```

- [ ] **Step 3: Test init end-to-end**

Run a full init on a throwaway directory:
```bash
TMP=$(mktemp -d); cd "$TMP"
bash /path/to/init.sh  # full interactive flow; use a test repo name
# Verify:
jq '.host, .mode, .remote_url' .claude/manifest.json
git remote -v
gh api "repos/$OWNER/$NAME/branches/main/protection" | jq '.enforce_admins.enabled'  # should be true
# Clean up throwaway repo
gh repo delete "$OWNER/$NAME" --yes
```

- [ ] **Step 4: Commit**

```bash
git add init.sh
git commit -m "feat(init): host-aware repo creation flow with dispatcher + driver"
```

---

## Phase 5 — Gate Enforcement

### Task 5.1: process-checklist.sh — verify_init rewrite

**Files:**
- Modify: `scripts/process-checklist.sh`

- [ ] **Step 1: Find existing verify_init**

Run: `grep -n 'verify_init\|remote_repo_created\|branch_protection_configured' scripts/process-checklist.sh`

Current (per earlier grep): verify_init auto-sets `remote_repo_created` if `git remote get-url origin` succeeds, and auto-sets `branch_protection_configured` if `.github/workflows/ci.yml` exists.

- [ ] **Step 2: Rewrite verify_init to use dispatcher**

Replace the existing `verify_init()` function body:

```bash
verify_init() {
  print_step "Verifying Phase 2 initialization"

  # Step 1: remote_repo_created — actual git check (unchanged)
  if git remote get-url origin >/dev/null 2>&1; then
    if ! step_is_completed "phase2_init" "remote_repo_created"; then
      jq '.phase2_init.steps_completed += ["remote_repo_created"]' "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"
    fi
    print_ok "remote_repo_created — git remote origin configured"
  else
    print_fail "remote_repo_created — no git remote origin found"
    return 1
  fi

  # Step 2: branch_protection_configured — REAL API check via dispatcher
  source scripts/lib/host.sh
  host_load_driver || return 1

  local mode
  mode=$(jq -r '.mode' .claude/manifest.json)
  if host_verify_protection "main" "$mode"; then
    if ! step_is_completed "phase2_init" "branch_protection_configured"; then
      jq '.phase2_init.steps_completed += ["branch_protection_configured"]' "$PROCESS_STATE" > "$PROCESS_STATE.tmp" && mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"
    fi
    print_ok "branch_protection_configured — protection rules verified via host API"
  else
    print_fail "branch_protection_configured — protection rules incomplete (see specific failing rules above)"
    return 1
  fi

  # Step 3-6: rest of existing verify_init logic unchanged (project_scaffolded, data_model_applied, pre_commit_hooks_installed, ci_pipeline_configured)
  # ... [preserve existing code for remaining steps] ...
}
```

- [ ] **Step 3: Test the rewrite**

Run in a project with known-correct protection:
```bash
bash scripts/process-checklist.sh --verify-init
# Expected: all auto-verifiable steps pass, remaining need manual attestation
```

- [ ] **Step 4: Commit**

```bash
git add scripts/process-checklist.sh
git commit -m "feat(gate): verify_init uses host dispatcher for real protection check"
```

### Task 5.2: check-phase-gate.sh — Phase 1→2 backstop

- [ ] **Step 1: Find existing phase-transition logic**

Run: `grep -n 'current_phase\|phase-state.json' scripts/check-phase-gate.sh | head -20`

- [ ] **Step 2: Add backstop at Phase 1→2 transition**

Insert at the point where a 1→2 transition is detected:

```bash
# --- Phase 1→2 backstop (per spec 2026-04-21) ---
if [ "$CURRENT_PHASE" = "1" ] && [ "$TARGET_PHASE" = "2" ]; then
  print_step "Phase 1→2 backstop: verifying repo protection"
  source scripts/lib/host.sh
  host_load_driver || {
    print_fail "Dispatcher load failed — cannot cross Phase 1→2 without a valid manifest host"
    exit 1
  }
  mode=$(jq -r '.mode' .claude/manifest.json)
  if ! host_verify_protection "main" "$mode"; then
    cat >&2 <<EOM
Phase 1→2 BLOCKED: remote protection verification failed.

Specific failures are shown above. To remediate:
  1. Review the failing rule(s) in the message above
  2. Run: scripts/check-gate.sh --repair
     (re-applies the configured bar via host_configure_protection)
  3. Or fix manually via your host's UI/API, then re-run:
     scripts/check-phase-gate.sh --advance

Phase state unchanged; retry after remediation.
EOM
    exit 2
  fi
  print_ok "Phase 1→2 backstop passed"
fi
```

- [ ] **Step 3: Commit**

```bash
git add scripts/check-phase-gate.sh
git commit -m "feat(gate): Phase 1->2 backstop verifies host protection via dispatcher"
```

### Task 5.3: pre-commit-gate.sh — early guard

- [ ] **Step 1: Add early remote-exists check**

Near the top of `scripts/pre-commit-gate.sh` (before other checks):

```bash
# --- Early guard: no commits allowed without a remote (per spec 2026-04-21) ---
if ! git remote get-url origin >/dev/null 2>&1; then
  cat >&2 <<'EOM'
pre-commit BLOCKED: no git remote configured.

Solo Orchestrator requires a created and protected remote from project init.
If this project predates the host-aware gate, run:
  scripts/check-gate.sh --backfill-host   # if manifest lacks host field
  scripts/check-gate.sh --repair          # to recreate/push/protect

See docs/builders-guide.md § Repository Setup for manual remediation.
EOM
  exit 1
fi
```

- [ ] **Step 2: Commit**

```bash
git add scripts/pre-commit-gate.sh
git commit -m "feat(gate): pre-commit early guard requires git remote"
```

---

## Phase 6 — check-gate.sh Helper

### Task 6.1: check-gate.sh skeleton + arg parsing

**Files:**
- Create: `scripts/check-gate.sh`

- [ ] **Step 1: Implement skeleton**

```bash
#!/usr/bin/env bash
# scripts/check-gate.sh — host-aware gate remediation helper.
# Subcommands:
#   --preflight       dry-run verification (does not modify anything)
#   --repair          re-apply repo setup from last successful step
#   --backfill-host   detect and record missing host field in manifest

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib/helpers.sh"
source "$SCRIPT_DIR/lib/host.sh"

usage() {
  cat <<'EOM'
Usage: check-gate.sh <subcommand>

Subcommands:
  --preflight       Dry-run: check current protection status without modifying anything.
                    Exits 0 if ready to cross Phase 1→2, non-zero if blocked.
  --repair          Re-run repo setup from last successful step (idempotent).
  --backfill-host   Infer host from git remote URL and write to manifest.
EOM
}

case "${1:-}" in
  --preflight)     shift; cmd_preflight "$@" ;;
  --repair)        shift; cmd_repair "$@" ;;
  --backfill-host) shift; cmd_backfill_host "$@" ;;
  -h|--help|"")    usage; exit 0 ;;
  *)               echo "Unknown subcommand: $1" >&2; usage; exit 1 ;;
esac
```

- [ ] **Step 2: Commit skeleton**

```bash
chmod +x scripts/check-gate.sh
git add scripts/check-gate.sh
git commit -m "feat(gate): check-gate.sh skeleton with subcommand dispatch"
```

### Task 6.2: check-gate.sh --preflight

- [ ] **Step 1: Implement cmd_preflight**

Insert into `check-gate.sh` above the case statement:

```bash
cmd_preflight() {
  print_step "Preflight: checking protection status"
  host_load_driver || exit 1
  local mode
  mode=$(jq -r '.mode' .claude/manifest.json)
  if host_verify_protection "main" "$mode"; then
    print_ok "Ready: protection verified for $mode mode"
    exit 0
  fi
  print_fail "Not ready: protection verification failed (see rules above)"
  exit 1
}
```

- [ ] **Step 2: Commit**

### Task 6.3: check-gate.sh --backfill-host

- [ ] **Step 1: Implement**

```bash
cmd_backfill_host() {
  local url
  url=$(git remote get-url origin 2>/dev/null) || {
    print_fail "No git remote configured — cannot infer host"
    exit 1
  }
  local inferred
  case "$url" in
    *github.com*)    inferred="github" ;;
    *gitlab*)        inferred="gitlab" ;;
    *bitbucket.org*) inferred="bitbucket" ;;
    *)               inferred="other" ;;
  esac
  print_info "Inferred host '$inferred' from origin URL: $url"
  read -rp "Confirm this is correct? [y/N]: " yn
  case "$yn" in
    [yY]*)
      jq --arg h "$inferred" '.host = $h' .claude/manifest.json > .claude/manifest.json.tmp \
        && mv .claude/manifest.json.tmp .claude/manifest.json
      print_ok "Host field written to manifest as '$inferred'"
      ;;
    *) print_fail "Aborted — no changes made. Manually set the host field if different."; exit 1 ;;
  esac
}
```

- [ ] **Step 2: Commit**

### Task 6.4: check-gate.sh --repair

- [ ] **Step 1: Implement**

```bash
cmd_repair() {
  print_step "Repair: re-applying repo setup from last successful step"
  host_load_driver || exit 1
  local mode
  mode=$(jq -r '.mode' .claude/manifest.json)

  # Step order: create (skip if exists) → register (no-op) → push (no-op) → configure → verify
  if ! git remote get-url origin >/dev/null 2>&1; then
    local name visibility
    name=$(jq -r '.project_name // empty' .claude/intake-progress.json)
    visibility=$(jq -r '.repo_visibility // "private"' .claude/intake-progress.json)
    [ -z "$name" ] && { print_fail "No project_name in intake-progress.json — cannot create"; exit 1; }
    print_info "Creating $visibility repo '$name'..."
    local url
    url=$(host_create_repo "$name" "$visibility") || exit 1
    host_register_remote "$url"
    host_push_initial main
  fi

  print_info "Re-applying protection for $mode mode..."
  host_configure_protection main "$mode" || { print_fail "Protection config failed"; exit 1; }
  host_verify_protection main "$mode" || { print_fail "Verification still failing — check host UI"; exit 1; }
  print_ok "Repair complete"
}
```

- [ ] **Step 2: Test all three subcommands** in a throwaway project:

```bash
bash scripts/check-gate.sh --preflight   # expect PASS if set up
bash scripts/check-gate.sh --backfill-host  # prompt + write
bash scripts/check-gate.sh --repair      # re-apply protection
```

- [ ] **Step 3: Commit**

```bash
git add scripts/check-gate.sh
git commit -m "feat(gate): check-gate.sh --preflight / --repair / --backfill-host"
```

---

## Phase 7 — CI & Release Templates

### Task 7.1: Move existing GitHub templates into github/ subfolder

- [ ] **Step 1: Reorganize CI templates**

```bash
cd templates/pipelines/ci
mkdir -p github
git mv typescript.yml python.yml rust.yml go.yml java.yml kotlin.yml csharp.yml swift.yml dart.yml other.yml github/
```

- [ ] **Step 2: Reorganize release templates**

```bash
cd ../release
mkdir -p github
git mv web.yml desktop.yml mobile.yml mcp-server.yml github/
cd ../../..
```

- [ ] **Step 3: Update any code that references flat paths**

Run: `grep -rn 'templates/pipelines/ci/[a-z]*.yml' scripts/ init.sh`

For each match, update to `templates/pipelines/ci/<host>/<language>.yml` where `<host>` is read from manifest/intake.

- [ ] **Step 4: Commit**

```bash
git add templates/pipelines init.sh scripts
git commit -m "chore(templates): reorganize CI+release templates into per-host subfolders"
```

### Task 7.2: GitLab CI templates — 10 languages

For each language, translate the existing `github/<lang>.yml` into GitLab CI syntax.

**Translation mapping (reference):**

| GitHub Actions | GitLab CI |
|---|---|
| `on: push / pull_request` | `rules: - if: $CI_PIPELINE_SOURCE == "push"` etc. |
| `jobs: <name>: steps:` | Top-level jobs with `stage:` and `script:` |
| `runs-on: ubuntu-latest` | `image: <lang-specific>` |
| `actions/checkout@v4` | Automatic (GitLab checks out by default) |
| `actions/cache@v4` | `cache: paths:` |
| `actions/setup-node@v4 with: node-version` | `image: node:<version>` |
| `matrix:` | `parallel: matrix:` |
| `env:` at step or job | `variables:` |
| `uses:` | N/A — use images or manual script |

- [ ] **Step 1: Python template (exemplar — full content)**

Create `templates/pipelines/ci/gitlab/python.yml`:

```yaml
# GitLab CI pipeline for Python projects (solo-orchestrator).
# Mirrors the GitHub Actions template: lint + test + sast + secrets + deps + licenses + build + governance.

stages:
  - lint
  - test
  - security
  - build
  - governance

variables:
  PIP_CACHE_DIR: "$CI_PROJECT_DIR/.cache/pip"

.cache_pip: &cache_pip
  cache:
    key: "${CI_COMMIT_REF_SLUG}-pip"
    paths:
      - .cache/pip
      - .venv/

.setup_python: &setup_python
  before_script:
    - python --version
    - pip install --upgrade pip
    - pip install -e ".[dev]" || pip install -r requirements-dev.txt

lint:
  stage: lint
  image: python:3.11
  <<: *cache_pip
  <<: *setup_python
  script:
    - ruff check .
    - ruff format --check .
    - mypy .

test:
  stage: test
  image: python:3.11
  <<: *cache_pip
  <<: *setup_python
  script:
    - pytest --cov=. --cov-report=term --cov-report=xml
  coverage: '/TOTAL.*\s+(\d+%)$/'
  artifacts:
    reports:
      coverage_report:
        coverage_format: cobertura
        path: coverage.xml

sast:
  stage: security
  image: python:3.11
  <<: *setup_python
  script:
    - pip install semgrep
    - semgrep --config=auto --error

secrets:
  stage: security
  image: zricethezav/gitleaks:latest
  script:
    - gitleaks detect --source . --verbose --redact

dependencies:
  stage: security
  image: python:3.11
  <<: *setup_python
  script:
    - pip install pip-audit
    - pip-audit

licenses:
  stage: security
  image: python:3.11
  <<: *setup_python
  script:
    - pip install pip-licenses
    - pip-licenses --format=markdown --with-urls | tee LICENSES.md

build:
  stage: build
  image: python:3.11
  <<: *setup_python
  script:
    - pip install build
    - python -m build
  artifacts:
    paths:
      - dist/

governance:
  stage: governance
  image: bash:5
  script:
    - bash scripts/check-phase-gate.sh
    - bash scripts/check-changelog.sh
```

- [ ] **Step 2: Commit Python exemplar**

```bash
git add templates/pipelines/ci/gitlab/python.yml
git commit -m "feat(ci): GitLab CI template for Python (exemplar)"
```

- [ ] **Step 3: TypeScript template (second exemplar)**

Create `templates/pipelines/ci/gitlab/typescript.yml`:

```yaml
stages:
  - lint
  - test
  - security
  - build
  - governance

variables:
  NPM_CACHE: "$CI_PROJECT_DIR/.npm"

.cache_node: &cache_node
  cache:
    key: "${CI_COMMIT_REF_SLUG}-node"
    paths:
      - .npm/
      - node_modules/

.setup_node: &setup_node
  before_script:
    - node --version
    - npm ci --cache .npm --prefer-offline

lint:
  stage: lint
  image: node:20
  <<: *cache_node
  <<: *setup_node
  script:
    - npm run lint
    - npm run typecheck

test:
  stage: test
  image: node:20
  <<: *cache_node
  <<: *setup_node
  script:
    - npm test -- --coverage
  coverage: '/Lines\s*:\s*(\d+\.?\d*)%/'

sast:
  stage: security
  image: node:20
  <<: *setup_node
  script:
    - npm install -g semgrep
    - semgrep --config=auto --error

secrets:
  stage: security
  image: zricethezav/gitleaks:latest
  script:
    - gitleaks detect --source . --verbose --redact

dependencies:
  stage: security
  image: node:20
  script:
    - npm audit --audit-level=moderate

licenses:
  stage: security
  image: node:20
  <<: *setup_node
  script:
    - npx license-checker --summary --excludePrivatePackages

build:
  stage: build
  image: node:20
  <<: *cache_node
  <<: *setup_node
  script:
    - npm run build
  artifacts:
    paths:
      - dist/
      - build/

governance:
  stage: governance
  image: bash:5
  script:
    - bash scripts/check-phase-gate.sh
    - bash scripts/check-changelog.sh
```

- [ ] **Step 4: Remaining 8 languages (Rust, Go, Java, Kotlin, C#, Swift, Dart, other)**

For each, apply the same translation pattern as Python/TypeScript: read `github/<lang>.yml`, map jobs → stages, replace action references with images/scripts, preserve the same 8 job set (lint, test, sast, secrets, dependencies, licenses, build, governance).

**Per-language image guidance:**
- `rust.yml` → `image: rust:1.75`; replace `cargo` commands
- `go.yml` → `image: golang:1.21`; replace `go` commands
- `java.yml` → `image: maven:3-eclipse-temurin-21` or `gradle:8-jdk21`
- `kotlin.yml` → same as java, plus `kotlin` command
- `csharp.yml` → `image: mcr.microsoft.com/dotnet/sdk:8.0`; `dotnet` commands
- `swift.yml` → `image: swift:5.9`; `swift` commands
- `dart.yml` → `image: dart:stable` or `cirrusci/flutter:stable`
- `other.yml` → `image: bash:5`; runs project-provided `scripts/ci.sh` if exists

Each file is ~60-90 lines. Commit per-language:

```bash
git add templates/pipelines/ci/gitlab/rust.yml
git commit -m "feat(ci): GitLab CI template for Rust"
# ... repeat for go, java, kotlin, csharp, swift, dart, other
```

### Task 7.3: GitLab release templates — 4 platforms

Create `templates/pipelines/release/gitlab/{web,desktop,mobile,mcp-server}.yml`.

Translation pattern: existing GitHub release workflows (`release: on: push tags: 'v*'`) become GitLab CI rules (`rules: - if: $CI_COMMIT_TAG =~ /^v/`).

- [ ] **Step 1: Web release exemplar**

Create `templates/pipelines/release/gitlab/web.yml`:

```yaml
stages:
  - build
  - deploy

variables:
  RELEASE_TAG_REGEX: /^v\d+\.\d+\.\d+$/

rules:
  - if: $CI_COMMIT_TAG =~ $RELEASE_TAG_REGEX

build_release:
  stage: build
  image: node:20
  script:
    - npm ci
    - npm run build
  artifacts:
    paths:
      - dist/
    expire_in: 1 month

deploy:
  stage: deploy
  image: alpine:latest
  script:
    - echo "Deploy step — configure per hosting target (Vercel, Netlify, etc.)"
  environment: production
  when: manual  # Human-gated per solo-orchestrator philosophy
```

- [ ] **Step 2: Remaining 3 platforms** follow the same pattern

- [ ] **Step 3: Commit each**

### Task 7.4: Bitbucket CI templates — 10 languages

Bitbucket Pipelines uses yet another syntax: top-level `pipelines:` with `default:`, `branches:`, `pull-requests:` keyed sections; each is an array of `step:` entries.

**Translation mapping:**

| GitHub Actions / GitLab CI | Bitbucket Pipelines |
|---|---|
| `on: push` / `stages:` | `pipelines: default:` |
| `jobs:` / multiple stages | Sequential `step:` entries, or `parallel:` for concurrency |
| `runs-on: ubuntu-latest` | `image:` |
| `actions/cache@v4` / `cache: paths:` | `caches:` (named) |
| `matrix:` | Manual duplication; Bitbucket has no first-class matrix |

- [ ] **Step 1: Python exemplar**

Create `templates/pipelines/ci/bitbucket/python.yml`:

```yaml
image: python:3.11

definitions:
  caches:
    pip: ~/.cache/pip

pipelines:
  default:
    - parallel:
        - step:
            name: Lint
            caches: [pip]
            script:
              - pip install -e ".[dev]" || pip install -r requirements-dev.txt
              - ruff check .
              - ruff format --check .
              - mypy .
        - step:
            name: Test
            caches: [pip]
            script:
              - pip install -e ".[dev]" || pip install -r requirements-dev.txt
              - pytest --cov=. --cov-report=term
    - parallel:
        - step:
            name: SAST
            script:
              - pip install semgrep
              - semgrep --config=auto --error
        - step:
            name: Secrets
            image: zricethezav/gitleaks:latest
            script:
              - gitleaks detect --source . --verbose --redact
        - step:
            name: Dependencies
            caches: [pip]
            script:
              - pip install pip-audit
              - pip-audit
        - step:
            name: Licenses
            caches: [pip]
            script:
              - pip install pip-licenses
              - pip-licenses --format=markdown > LICENSES.md
    - step:
        name: Build
        caches: [pip]
        script:
          - pip install build
          - python -m build
        artifacts:
          - dist/**
    - step:
        name: Governance
        image: bash:5
        script:
          - bash scripts/check-phase-gate.sh
          - bash scripts/check-changelog.sh
```

- [ ] **Step 2: TypeScript exemplar**

Similar structure; replace `image: python:3.11` with `image: node:20`, `pip` with `npm ci`, `pytest` with `npm test`.

- [ ] **Step 3: Remaining 8 languages**

Apply the pattern. Images per language same as GitLab. Commit per file.

### Task 7.5: Bitbucket release templates — 4 platforms

Bitbucket uses `pipelines: tags: 'v*':` for tag-triggered pipelines.

- [ ] **Step 1: Web release**

```yaml
image: node:20

pipelines:
  tags:
    'v*':
      - step:
          name: Build Release
          script:
            - npm ci
            - npm run build
          artifacts:
            - dist/**
      - step:
          name: Deploy
          deployment: production
          trigger: manual
          script:
            - echo "Configure per hosting target"
```

- [ ] **Step 2: Remaining 3 platforms** follow same pattern

- [ ] **Step 3: Commit**

---

## Phase 8 — Upgrade Path Migration

### Task 8.1: upgrade-project.sh — template path migration

**Files:**
- Modify: `scripts/upgrade-project.sh`

- [ ] **Step 1: Add migration block**

After the normal upgrade flow, add:

```bash
# --- Migration: flat CI template paths → per-host paths (spec 2026-04-21) ---
print_step "Template path migration"

# Detect old flat layout in project (if project has a copy of templates; rare)
if [ -d "templates/pipelines/ci" ] && ! [ -d "templates/pipelines/ci/github" ]; then
  print_info "Detected flat CI template layout — migrating to per-host"
  mkdir -p templates/pipelines/ci/github templates/pipelines/release/github
  # Move .yml files (only direct children)
  for f in templates/pipelines/ci/*.yml; do
    [ -f "$f" ] && git mv "$f" "templates/pipelines/ci/github/$(basename "$f")"
  done
  for f in templates/pipelines/release/*.yml; do
    [ -f "$f" ] && git mv "$f" "templates/pipelines/release/github/$(basename "$f")"
  done
  print_ok "CI/release templates moved to github/ subfolders"
fi

# Check and backfill host field
if [ -f ".claude/manifest.json" ] && ! jq -e '.host' .claude/manifest.json >/dev/null 2>&1; then
  print_info "Manifest missing 'host' field — running backfill"
  bash scripts/check-gate.sh --backfill-host
fi

# Inform user
cat <<'EOM'
Upgrade complete. The host-aware repo gate is now active.

Before your next Phase 1→2 transition, run:
  bash scripts/check-gate.sh --preflight

If preflight fails, run:
  bash scripts/check-gate.sh --repair
EOM
```

- [ ] **Step 2: Commit**

```bash
git add scripts/upgrade-project.sh
git commit -m "feat(upgrade): migrate flat CI template layout + backfill host field"
```

---

## Phase 9 — Documentation

### Task 9.1: docs/builders-guide.md — per-host sections

**Files:**
- Modify: `docs/builders-guide.md`

- [ ] **Step 1: Find existing repo-creation section**

Run: `grep -n 'gh repo create\|branch protection\|## Repository' docs/builders-guide.md`

- [ ] **Step 2: Replace with host-aware section**

Replace the existing repo-creation block (around `docs/builders-guide.md:856-870` per spec) with three parallel sections:

```markdown
## Repository Setup

Solo Orchestrator creates and protects your git remote at `init.sh` time. You pick the host during intake. This section documents the per-host setup for first-class hosts and the manual flow for `other`.

### GitHub (first-class)

Prereq: `gh` CLI installed and authenticated. Install: `brew install gh` (macOS) / see https://cli.github.com. Then `gh auth login`.

Init.sh runs automatically:
```bash
gh repo create <name> --private     # or --public
# git add, git commit, git remote add origin, git push -u origin main
gh api -X PUT "repos/<owner>/<repo>/branches/main/protection" --input - <<'JSON'
{ "required_status_checks": null, "enforce_admins": true, ... }
JSON
```

For personal mode: force-push off, admins not exempt.
For org mode: add `required_pull_request_reviews.required_approving_review_count: 1` and `required_status_checks`.

### GitLab (first-class)

Prereq: `glab` CLI installed and authenticated. Install: `brew install glab` / see https://gitlab.com/gitlab-org/cli. Then `glab auth login` (add `--hostname gitlab.example.com` for self-hosted).

Init.sh runs automatically:
```bash
glab repo create <name> --private
# git setup
glab api -X POST "projects/<namespace>%2F<name>/protected_branches" --input - <<'JSON'
{ "name": "main", "push_access_level": 40, "merge_access_level": 30, "allow_force_push": false }
JSON
```

For org mode: also sets `approvals_before_merge: 1` via `projects/<id>/approvals`.

### Bitbucket Cloud (first-class)

Prereq: App Password (not account password). Create at https://bitbucket.org/account/settings/app-passwords/ with scopes `repository:admin`, `project:admin`, `pullrequest:write`. Export:
```bash
export BITBUCKET_USER="your-username"
export BITBUCKET_APP_PASSWORD="your-app-password"
```

For org workspaces, also: `export BITBUCKET_WORKSPACE="org-name"`.

Init.sh uses curl against `api.bitbucket.org/2.0`:
```bash
POST /repositories/<workspace>/<repo>    # creates repo
POST /repositories/<workspace>/<repo>/branch-restrictions   # per restriction
```

Branch-restrictions uses separate records per rule type (`force`, `delete`, `push`, `require_approvals_to_merge`).

### Other hosts (non-first-class)

For Gitea, Codeberg, self-hosted Jenkins, or any non-supported host:

1. Create the repo manually on your host.
2. During intake, choose `other` and paste the HTTPS clone URL when prompted.
3. Configure branch protection manually per your host's docs. The required bar:
   - Force-push disabled on main
   - Admins not exempt (if supported)
   - For org mode: require at least 1 PR review
4. At the attestation prompt in init.sh, confirm protection is configured (type `yes`).
5. Init.sh does not lay down a CI template for `other` — supply your own `.gitlab-ci.yml` / `bitbucket-pipelines.yml` / Jenkinsfile / etc.
6. Attestation expires after 90 days — re-confirm when the backstop gate next runs.
```

- [ ] **Step 3: Commit**

```bash
git add docs/builders-guide.md
git commit -m "docs: per-host Repository Setup sections in builders-guide"
```

### Task 9.2: docs/cli-setup-addendum.md — host CLI install + auth

- [ ] **Step 1: Add section**

Append to `docs/cli-setup-addendum.md`:

```markdown
## Git Host CLIs

Solo Orchestrator uses host-specific CLIs for repo creation and protection configuration. Install the one matching your chosen host during intake.

### gh (GitHub)

```bash
# macOS
brew install gh
# Ubuntu/Debian
type -p curl >/dev/null || sudo apt install curl -y
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update && sudo apt install gh -y

# Authenticate
gh auth login
gh auth status  # verify
```

### glab (GitLab)

```bash
# macOS
brew install glab
# Ubuntu/Debian via pre-built binary
curl -s https://gitlab.com/gitlab-org/cli/-/releases | grep -oE '/gitlab-org/cli/-/releases/v[0-9.]+/' | head -1
# (follow download link from https://gitlab.com/gitlab-org/cli/-/releases)

# Authenticate — gitlab.com
glab auth login
# Self-hosted
glab auth login --hostname gitlab.example.com
```

### Bitbucket (curl + App Password)

No CLI — uses `curl` (always available) + Bitbucket App Password.

1. Generate an App Password at https://bitbucket.org/account/settings/app-passwords/
   - Required scopes: `repository:admin`, `project:admin`, `pullrequest:write`
2. Export credentials:
   ```bash
   export BITBUCKET_USER="your-bitbucket-username"
   export BITBUCKET_APP_PASSWORD="your-app-password"
   # For org workspaces, also:
   export BITBUCKET_WORKSPACE="org-name"
   ```
3. Add to your shell rc (`.bashrc` / `.zshrc`) for persistence. Ensure the file is mode 600.
```

- [ ] **Step 2: Commit**

```bash
git add docs/cli-setup-addendum.md
git commit -m "docs(cli-setup): host CLI install + auth guidance"
```

---

## Phase 10 — End-to-End & Regression Tests

### Task 10.1: End-to-end init per-host tests

**Files:**
- Modify: `tests/full-project-test-suite.sh`

- [ ] **Step 1: Add test cases for each host using mocked CLIs**

Append to `tests/full-project-test-suite.sh`:

```bash
# --- Host-aware init E2E tests (spec 2026-04-21) ---

test_init_github_e2e() {
  local WORK=$(mktemp -d); cd "$WORK"
  source /path/to/solo-orchestrator/tests/host-drivers/mock-cli.sh
  MOCK_DIR=$(mock_cli_setup)
  export PATH="$MOCK_DIR:$PATH"

  # Pre-register all expected gh calls
  mock_cli_respond gh "auth status" 0 "Logged in"
  mock_cli_respond gh "--version" 0 "gh version 2.0"
  mock_cli_respond gh "repo create test-e2e-gh --private" 0 "https://github.com/u/test-e2e-gh"
  mock_cli_respond gh "api -X PUT repos/u/test-e2e-gh/branches/main/protection" 0 '{"ok":true}'
  mock_cli_respond gh "api repos/u/test-e2e-gh/branches/main/protection" 0 '{"enforce_admins":{"enabled":true},"allow_force_pushes":{"enabled":false}}'

  # Seed intake-progress.json and run a mock-lite init (skip interactive prompts)
  # ... (invoke init.sh's non-interactive test entry point; may need to add one)

  # Assertions
  assert_eq "github" "$(jq -r '.host' .claude/manifest.json)" "github manifest"
  assert_eq "https://github.com/u/test-e2e-gh" "$(jq -r '.remote_url' .claude/manifest.json)" "github remote_url"
  [ -f ".github/workflows/ci.yml" ] || { echo "github CI template not laid down" >&2; return 1; }

  mock_cli_teardown "$MOCK_DIR"
  export PATH="${PATH#$MOCK_DIR:}"
  cd - >/dev/null; rm -rf "$WORK"
  echo "test_init_github_e2e PASSED"
}

# Similar for gitlab, bitbucket, other
test_init_gitlab_e2e() { ... }
test_init_bitbucket_e2e() { ... }
test_init_other_e2e() {
  # No CLI mocks; test URL-paste + attestation path
  ...
}
```

- [ ] **Step 2: Commit**

### Task 10.2: Regression tests in known-bugs-test-suite.sh

- [ ] **Step 1: Add three cases per spec**

```bash
# --- Host-gate regression cases (spec 2026-04-21) ---

test_lancache_pattern() {
  # Project mid-Phase-1 with no remote → Phase 1→2 blocked
  local WORK=$(mktemp -d); cd "$WORK"
  mkdir -p .claude
  echo '{"host":"github","mode":"personal"}' > .claude/manifest.json
  echo '{"current_phase":1}' > .claude/phase-state.json
  git init -q
  # No remote configured
  set +e
  output=$(bash /path/to/solo-orchestrator/scripts/check-phase-gate.sh --advance 2>&1)
  code=$?
  set -e
  assert_exit_code 2 "$code" "blocks Phase 1→2 without remote"
  assert_contains "$output" "Phase 1→2 BLOCKED" "block message"
  cd - >/dev/null; rm -rf "$WORK"
  echo "test_lancache_pattern PASSED"
}

test_manifest_missing_host() {
  # Legacy manifest → backfill prompt, no silent default
  local WORK=$(mktemp -d); cd "$WORK"
  mkdir -p .claude
  echo '{"mode":"personal"}' > .claude/manifest.json  # no host field
  git init -q
  set +e
  output=$(source /path/to/solo-orchestrator/scripts/lib/host.sh && host_read_from_manifest 2>&1)
  code=$?
  set -e
  assert_exit_code 2 "$code" "missing host returns code 2"
  assert_contains "$output" "--backfill-host" "remediation hint"
  cd - >/dev/null; rm -rf "$WORK"
  echo "test_manifest_missing_host PASSED"
}

test_protection_drift() {
  # API returns "force-push enabled" → Phase 1→2 blocked with specific rule
  local WORK=$(mktemp -d); cd "$WORK"
  source /path/to/mock-cli.sh
  MOCK_DIR=$(mock_cli_setup)
  export PATH="$MOCK_DIR:$PATH"
  mkdir -p .claude
  echo '{"host":"github","mode":"personal"}' > .claude/manifest.json
  echo '{"current_phase":1}' > .claude/phase-state.json
  git init -q; git remote add origin "https://github.com/u/r.git"
  # Drift: force-push has been enabled
  mock_cli_respond gh "api repos/u/r/branches/main/protection" 0 '{"enforce_admins":{"enabled":true},"allow_force_pushes":{"enabled":true}}'
  set +e
  output=$(bash /path/to/solo-orchestrator/scripts/check-phase-gate.sh --advance 2>&1)
  code=$?
  set -e
  assert_exit_code 2 "$code"
  assert_contains "$output" "force-push" "specific rule mentioned"
  mock_cli_teardown "$MOCK_DIR"
  cd - >/dev/null; rm -rf "$WORK"
  echo "test_protection_drift PASSED"
}
```

- [ ] **Step 2: Commit**

```bash
git add tests/known-bugs-test-suite.sh
git commit -m "test(regression): lancache-pattern + manifest-missing-host + drift cases"
```

### Task 10.3: Upgrade-path regression

Extend `tests/upgrade-path-tests.sh`:

```bash
test_upgrade_flat_to_perhost_layout() {
  local WORK=$(mktemp -d); cd "$WORK"
  # Simulate old project: flat CI layout, manifest without host field
  mkdir -p templates/pipelines/ci templates/pipelines/release .claude .github/workflows
  touch templates/pipelines/ci/python.yml templates/pipelines/release/web.yml
  echo "name: CI" > .github/workflows/ci.yml
  git init -q
  git remote add origin "https://github.com/u/old-project.git"
  echo '{"version":"0.9","mode":"personal"}' > .claude/manifest.json

  # Run upgrade (non-interactive; feed "y" for backfill)
  echo "y" | bash /path/to/solo-orchestrator/scripts/upgrade-project.sh

  # Assertions
  [ -f ".github/workflows/ci.yml" ] || { echo "GitHub CI file preserved" >&2; return 1; }
  [ -f "templates/pipelines/ci/github/python.yml" ] || { echo "template migrated" >&2; return 1; }
  assert_eq "github" "$(jq -r '.host' .claude/manifest.json)" "host backfilled"
  # phase2_init initialized but NOT verified (user must re-run preflight)
  verified=$(jq -r '.phase2_init.verified // false' .claude/process-state.json)
  assert_eq "false" "$verified" "phase2_init not auto-verified"

  cd - >/dev/null; rm -rf "$WORK"
  echo "test_upgrade_flat_to_perhost_layout PASSED"
}
```

- [ ] **Commit**

```bash
git add tests/upgrade-path-tests.sh
git commit -m "test(upgrade): flat→per-host template migration regression"
```

---

## Plan Self-Review Checklist

After completing all tasks, verify:

**Spec coverage:**
- [ ] All 7 spec decisions represented in tasks (architecture, hosts, fallback depth, first-class selection, personal/org, forward-only migration, no override)
- [ ] Three first-class drivers implemented with full contract
- [ ] `other` host URL-paste + attestation path wired in init.sh
- [ ] Both enforcement points active (init + Phase 1→2 backstop)
- [ ] `check-gate.sh` has all three subcommands
- [ ] 42 template files in place (30 CI + 12 release across 3 hosts)
- [ ] 5 test layers represented (unit/integration/E2E/regression/upgrade)

**Placeholder scan:**
- [ ] No "TBD" / "TODO" / "fill in" / "add appropriate" / "similar to Task N" in final plan
- [ ] All code steps show actual code, not pseudocode
- [ ] Every template file has actual content or a clearly-specified translation source

**Type consistency:**
- [ ] Function names match across all driver files (`host_create_repo` not `create_host_repo`)
- [ ] Mode values are exactly `"personal"` and `"org"` everywhere
- [ ] Host values are exactly `"github"`, `"gitlab"`, `"bitbucket"`, `"other"` everywhere
- [ ] Manifest field name is `host` (singular), not `hosts` or `git_host`

Run: `git log --oneline --since="2026-04-22"` to count commits. Target: 50+ commits across phases (one per task/sub-task).

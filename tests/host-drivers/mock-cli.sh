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
  # Stdin discipline: drain any piped payload before exiting. The bitbucket
  # driver pipes JSON to `curl --data-binary @-`; the gitlab driver pipes
  # JSON to `glab api ... --input -`. Without draining, the producer can
  # race against stub exit (SIGPIPE) or leave bytes in the pipe buffer.
  # `cat >/dev/null` is a no-op when nothing is piped (read returns EOF
  # immediately), so this is safe for all callers.
  #
  # Stderr discipline: stubs MUST NOT write to stderr on the success path —
  # the bitbucket driver merges stderr into stdout via `curl ... 2>&1`, so
  # any stray diagnostic gets folded into the response body and crashes jq
  # downstream. Stderr is only emitted from the unmatched-fixture branch
  # (intentional failure mode, exit 127).
  cat > "$stub" <<'STUB_EOF'
#!/usr/bin/env bash
fixture_dir="$(dirname "$0")/.fixtures"
cli="$(basename "$0")"
args="$*"
# Drain stdin if data is piped in (POST/PUT bodies). Stdin from a terminal
# would block read; check first via `[ -t 0 ]`. When a pipe/file is on stdin
# (`[ -t 0 ]` false), read+discard everything.
if [ ! -t 0 ]; then
  cat >/dev/null 2>&1 || true
fi
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

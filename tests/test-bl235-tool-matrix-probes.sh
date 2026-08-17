#!/usr/bin/env bash
# tests/test-bl235-tool-matrix-probes.sh
#
# BL-235 — the tool matrix records "Qdrant MCP installed" from a CONFIG ENTRY
# and never asks the database. `check_command` greps `~/.claude.json` for an
# `mcpServers.qdrant` key and `version_command` is `echo 'configured'` — a value
# that cannot be wrong, and therefore carries no information. A project with no
# running database is recorded `already_installed` and reported `[OK]` by every
# surface that consumes the resolver.
#
# ── THE SWEEP, ACROSS ALL FOUR MATRICES ─────────────────────────────────────
# A first draft of this file swept `common.json` ALONE and called that "the
# sweep the entry asked for, RUN". It was one of four. Derive the truth rather
# than trusting this comment — note the `for f in` over the whole directory,
# which is the correction:
#
#   for f in templates/tool-matrix/*.json; do
#     jq -r '.tools | to_entries[]
#            | select((.value.version_command // "") | test("^echo "))
#            | .value.name' "$f"
#   done
#
# On the pre-fix tree that returned ELEVEN rows across TEN distinct tools —
# three in common.json (Qdrant MCP, Context7 MCP, Superpowers) and eight more in
# desktop/mobile/web (dart_license_checker twice, both Apple Developer Program
# rows, the EV Code Signing Certificate, Android Keystore, OWASP ZAP and Android
# Studio). `Android Studio` carried the defect in BOTH fields: its check was
# `[ -d "$HOME/Library/Android/sdk" ] || [ -n "$ANDROID_HOME" ]`, which is true
# of an empty directory and of a stale export — a declaration, not a working
# SDK. D1/D1b/D2 now assert over every matrix file, so the next one cannot hide.
#
# ── THE PREREQUISITE, MEASURED, AND WHY IT COMES FIRST ──────────────────────
# The entry says a probe is unsafe because "the matrix schema does not currently
# express a bound". That is half right, and the half that is wrong changes the
# design:
#
#   scripts/resolve-tools.sh   run_with_deadline "$RESOLVE_TOOLS_EVAL_TIMEOUT"  BOUNDED (10s)
#   scripts/check-versions.sh  eval "$CHECK_CMD"                                UNBOUNDED
#
# Two consumers of the same data, asymmetric bounding — and the unbounded one is
# ALREADY a live hazard: the matrix ships `colima version` as a version command
# (grep it in templates/tool-matrix/common.json), and resolve-tools.sh's own
# header records that daemon-backed commands "can hang indefinitely when the
# daemon is unreachable", which is why IT bounds them.
# (`docker --version` is NOT one of them, and an earlier draft of this comment
# named it as the example. It is client-only — a compiled-in string, no socket —
# measured at 26ms on this host. `docker version`, without the dashes, is the
# one that talks to the daemon. The hazard is real; that example was not.)
# So check-versions.sh could hang today, before this entry adds anything. Adding
# a network probe to the matrix without bounding that consumer would put a third
# hang path into the one script that cannot survive it. T1/T2 pin the bound;
# everything else depends on it. T4 pins its COST, which is a separate question
# from its existence and was answered wrongly once.
#
# ASSERTIONS ARE WALL CLOCK, EXIT CODES AND EMITTED STATE — never the presence
# of a call. A probe that is merely ATTEMPTED is the defect restated.
#
# ── ASSERT THE STATE YOU MEAN, NEVER ITS COMPLEMENT ─────────────────────────
# The first version of D3 asserted `rc -ne 0` where the truth is exactly `2`.
# That passes on `rc=127` — the probe script was never FOUND — and it is why
# nothing here caught the rows becoming CWD-relative. The three-state contract
# the probe header spends ten lines defending had zero coverage. Every state is
# now asserted by equality, and C1 measures the contract where a caller actually
# consumes it rather than where this file can most conveniently reach it.
#
# Hermetic: temp dirs, stub binaries on PATH, a loopback-only stub HTTP server,
# no external network, no real database. bash 3.2 safe. No `timeout`/`gtimeout`
# (absent on the dev host).

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECKVER="$REPO_ROOT/scripts/check-versions.sh"
PROBE="$REPO_ROOT/scripts/probe-tool.sh"
MATRIX_DIR="$REPO_ROOT/templates/tool-matrix"
MATRIX="$MATRIX_DIR/common.json"

BASH_BIN="$(command -v bash)"; [ -n "$BASH_BIN" ] || BASH_BIN="/bin/bash"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip_() { echo "  [SKIP] $1 — $2"; }

if ! command -v jq >/dev/null 2>&1; then
  echo "  [SKIP] jq is not installed — this suite asserts on matrix JSON."
  echo ""; echo "Results: 0 passed, 0 failed"; exit 0
fi

TOPTMP="$(mktemp -d)"
STUB_PID=""
cleanup() {
  [ -n "$STUB_PID" ] && kill "$STUB_PID" 2>/dev/null
  chmod -R u+rwX "$TOPTMP" 2>/dev/null
  rm -rf "$TOPTMP"
}
trap cleanup EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/caseXXXXXX"; }

_num() { case "$1" in ''|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$1" ;; esac }
_mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || printf '?\n'; }
_sites() { local n; n=$(grep -c "$2\$" "$1" 2>/dev/null); _num "$n"; }
_changed_lines() { local n; n=$(diff "$1" "$2" 2>/dev/null | grep -c '^[<>]'); _num "$n"; }

# _mutate <file> <end-of-line marker> <replacement line>
# Replaces every line ENDING in the marker. Returns "sites changed parses".
#
# THE DELIMITER IS \001, NOT A PRINTABLE CHARACTER. `|` is out because shell
# replacements are `||`-dense and sed terminates the expression early while
# reporting success. `%` replaced it and lasted exactly one case: a mutant
# containing `printf %s` produced `bad flag in substitute command`, and the
# mutant then reported sites=0 — a mutation proof that silently proved nothing.
# `@` fails identically on `superpowers@claude-plugins-official`. A control
# character cannot occur in a shell one-liner, so the class is closed rather
# than dodged. `&` is still escaped, because an unescaped one splices the whole
# match back in and that mutant passes `bash -n`.
_mutate() {
  local f="$1" marker="$2" repl="$3" before sites changed parses safe mode tmp d
  d=$(printf '\001')
  safe=$(printf '%s' "$repl" | sed 's/&/\\&/g')
  mode="$(_mode_of "$f")"
  before="$(mktemp)"; cp -p "$f" "$before"
  sites=$(_sites "$f" "$marker")
  tmp="$(mktemp)"
  sed "s${d}^.*${marker}\$${d}${safe}${d}" "$f" > "$tmp" && mv "$tmp" "$f"
  [ "$mode" != "?" ] && chmod "$mode" "$f" 2>/dev/null
  changed=$(_changed_lines "$before" "$f")
  parses=0; bash -n "$f" >/dev/null 2>&1 && parses=1
  rm -f "$before"
  printf '%s %s %s\n' "$sites" "$changed" "$parses"
}

# _mutate_json <file> <jq filter> — rewrite a matrix file through jq. Returns
# "changed parses" (parses = the result is still valid JSON).
_mutate_json() {
  local f="$1" filter="$2" before changed parses tmp
  before="$(mktemp)"; cp -p "$f" "$before"
  tmp="$(mktemp)"
  if jq "$filter" "$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then mv "$tmp" "$f"; else rm -f "$tmp"; fi
  changed=$(_changed_lines "$before" "$f")
  parses=0; jq -e . "$f" >/dev/null 2>&1 && parses=1
  rm -f "$before"
  printf '%s %s\n' "$changed" "$parses"
}

# mk_matrix_proj <dir> <check_cmd> <version_cmd> — a project whose matrix holds
# exactly one tool, with the given commands. check-versions.sh reads
# templates/tool-matrix relative to CWD.
mk_matrix_proj() {
  local d="$1" chk="$2" ver="$3"
  mkdir -p "$d/templates/tool-matrix" "$d/.claude"
  jq -n --arg c "$chk" --arg v "$ver" \
    '{description:"fixture", schema_version:1, scope:"common",
      tools:{ Probe:{ name:"Probe", category:"mcp_server", phase:2, required:false,
                      check_command:$c, version_command:$v, description:"fixture row" } } }' \
    > "$d/templates/tool-matrix/common.json"
}

# mk_shipped_row_proj <dir> <tool name> — a project whose matrix holds exactly
# the row the framework SHIPS for that tool, copied verbatim. Used to measure
# the row where a consumer evaluates it rather than where this file can most
# easily reach it.
#
# `.tools` IS AN ARRAY in all four shipped matrices. `to_entries | from_entries`
# round-trips an OBJECT; on an array it yields integer keys and jq dies with
# "Cannot use number (13) as object key" — after which this fixture writes an
# EMPTY file and the case fails for a reason that has nothing to do with the
# defect. `map(select(...))` is the array-shaped form.
mk_shipped_row_proj() {
  local d="$1" tool="$2"
  mkdir -p "$d/templates/tool-matrix" "$d/.claude"
  jq --arg t "$tool" \
    '{description:"fixture", schema_version:1, scope:"common",
      tools: (.tools | map(select(.name == $t)))}' \
    "$MATRIX" > "$d/templates/tool-matrix/common.json"
  [ -s "$d/templates/tool-matrix/common.json" ] || return 1
  [ "$(jq '.tools | length' "$d/templates/tool-matrix/common.json" 2>/dev/null)" = "1" ] || return 1
}

# ── the stub HTTP server ────────────────────────────────────────────────────
# ONE loopback server, many routes, so the suite pays one startup. QDRANT_URL
# carries the route as a path prefix; the probe appends `/`.
STUB_PORT=""
start_stub() {
  command -v python3 >/dev/null 2>&1 || return 1
  local d="$TOPTMP/stub" i=0
  mkdir -p "$d"
  cat > "$d/routes.json" <<'ROUTES'
{
  "/qdrant/":    {"body": {"title": "qdrant - vector search engine", "version": "1.17.1", "commit": "deadbee"}},
  "/dbnine/":    {"body": {"title": "qdrant - vector search engine", "version": "9.9.9"}},
  "/notqdrant/": {"body": {"name": "totally-not-qdrant", "version": "8.11.0"}},
  "/esshape/":   {"body": {"title": "es", "version": {"number": "8.11.0", "build_flavor": "default"}}},
  "/authed/":    {"api_key": "s3cr3t", "body": {"title": "qdrant - vector search engine", "version": "1.17.1"}},
  "/ctx7/":      {"body": {"jsonrpc": "2.0"}}
}
ROUTES
  cat > "$d/stub.py" <<'PY'
import json, os
from http.server import BaseHTTPRequestHandler, HTTPServer

ROUTES = json.load(open(os.environ["STUB_ROUTES"]))

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        r = ROUTES.get(self.path)
        if r is None:
            self._send(404, b'{"status":{"error":"Not found"}}')
            return
        need = r.get("api_key")
        if need and self.headers.get("api-key") != need:
            self._send(403, b'{"status":{"error":"Must provide an API key or an Authorization bearer token"}}')
            return
        self._send(r.get("code", 200), json.dumps(r.get("body", {})).encode())

    def _send(self, code, body):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass

srv = HTTPServer(("127.0.0.1", 0), H)
print(srv.server_port, flush=True)
srv.serve_forever()
PY
  STUB_ROUTES="$d/routes.json" python3 "$d/stub.py" > "$d/port.txt" 2>"$d/err.txt" &
  STUB_PID=$!
  while [ "$i" -lt 60 ]; do
    STUB_PORT="$(head -1 "$d/port.txt" 2>/dev/null)"
    case "$STUB_PORT" in ''|*[!0-9]*) : ;; *) return 0 ;; esac
    sleep 0.1
    i=$((i + 1))
  done
  STUB_PORT=""
  return 1
}

# mk_qdrant_home <dir> <url> [api-key] — a HOME whose ~/.claude.json registers
# the qdrant MCP server at the given URL.
mk_qdrant_home() {
  local h="$1" url="$2" key="${3:-}"
  mkdir -p "$h"
  if [ -n "$key" ]; then
    jq -n --arg u "$url" --arg k "$key" \
      '{mcpServers:{qdrant:{command:"uvx", env:{QDRANT_URL:$u, QDRANT_API_KEY:$k}}}}' > "$h/.claude.json"
  else
    jq -n --arg u "$url" \
      '{mcpServers:{qdrant:{command:"uvx", env:{QDRANT_URL:$u}}}}' > "$h/.claude.json"
  fi
}

# probe_rc <home> <cwd> <args...> — run the SHIPPED probe with a controlled HOME
# from a controlled CWD. Echoes the exit code.
probe_rc() {
  local home="$1" cwd="$2"; shift 2
  local rc=0
  ( cd "$cwd" && HOME="$home" PROBE_QUIET=1 "$BASH_BIN" "$PROBE" "$@" >/dev/null 2>&1 ) || rc=$?
  printf '%s\n' "$rc"
}

echo "=== T — the unbounded consumer is bounded (the prerequisite) ==="

# ── T1: a check_command that sleeps must NOT hold check-versions.sh for its
# full duration. Asserted on WALL CLOCK, because "a timeout exists" is a claim
# and elapsed seconds are a measurement.
T1="$(newtmp)"; mk_matrix_proj "$T1" 'sleep 12' "echo 1.0"
t1_start=$(date +%s)
( cd "$T1" && CHECKVER_EVAL_TIMEOUT=2 "$BASH_BIN" "$CHECKVER" >/dev/null 2>&1 ) || true
t1_elapsed=$(( $(date +%s) - t1_start ))
if [ "$t1_elapsed" -lt 9 ]; then
  pass "T1: a 12s check_command did not hold check-versions.sh for 12s (elapsed ${t1_elapsed}s) — the eval is bounded, so a matrix row can probe without freezing the one consumer that never had a timeout"
else
  fail_ "T1" "elapsed ${t1_elapsed}s for a 12s check_command at a 2s bound — the eval is unbounded, and the matrix already ships 'colima version', which hangs when the daemon is unreachable"
fi

# ── T2: the same for version_command. Both evals were unbounded, and a probe
# would most naturally live in the version command.
T2="$(newtmp)"; mk_matrix_proj "$T2" 'true' 'sleep 12'
t2_start=$(date +%s)
( cd "$T2" && CHECKVER_EVAL_TIMEOUT=2 "$BASH_BIN" "$CHECKVER" >/dev/null 2>&1 ) || true
t2_elapsed=$(( $(date +%s) - t2_start ))
if [ "$t2_elapsed" -lt 9 ]; then
  pass "T2: a 12s version_command is bounded too (elapsed ${t2_elapsed}s) — bounding only the check would leave the other half of every row unbounded"
else
  fail_ "T2" "elapsed ${t2_elapsed}s for a 12s version_command at a 2s bound"
fi

# ── T2b: A PIPELINE, WHICH IS THE SHAPE THE MATRIX ACTUALLY SHIPS.
#
# T2 above passes on `sleep 12` and certified the bound using the ONE shape that
# works. `kill -9` reaps the `bash -c` child; a pipeline's other members survive
# it holding the pipe open, and a caller reading through a COMMAND SUBSTITUTION
# then waits for THEM. Measured before the fix: `sleep 12 | cat` at a 2s bound
# took 12s, as did `(sleep 12)` and the verbatim shipped Colima row
# (`colima version … | head -1 | awk …`). 21 of the 41 checkable rows across the
# four matrices are that shape, so the bound was decorative for half the matrix
# — including the daemon-backed rows it exists for.
#
# Derive the reach rather than trusting this comment:
#   for f in templates/tool-matrix/*.json; do
#     jq -r '.tools[] | select((.version_command // "") | test("[|]|[(]|&")) | .name' "$f"
#   done | wc -l
T2B="$(newtmp)"; mk_matrix_proj "$T2B" 'true' 'sleep 12 | cat'
t2b_start=$(date +%s)
( cd "$T2B" && CHECKVER_EVAL_TIMEOUT=2 "$BASH_BIN" "$CHECKVER" >/dev/null 2>&1 ) || true
t2b_elapsed=$(( $(date +%s) - t2b_start ))
if [ "$t2b_elapsed" -lt 9 ]; then
  pass "T2b: a 12s PIPELINE version_command is bounded too (elapsed ${t2b_elapsed}s) — the reader takes the output through a file, so an unreaped pipeline member holding the write end can no longer outlast the bound"
else
  fail_ "T2b" "elapsed ${t2b_elapsed}s for a 12s pipeline at a 2s bound — the bound reaps only the 'bash -c' child, and a command substitution waits for every other writer. This is the shape 21 of 41 shipped rows use, Colima included"
fi

# ── T3: the bound must not break a NORMAL row. Over-tightening would turn every
# healthy tool into 'not installed', which is the same class of wrong answer.
T3="$(newtmp)"; mk_matrix_proj "$T3" 'true' "echo 9.9.9"
t3_out="$( cd "$T3" && "$BASH_BIN" "$CHECKVER" 2>&1 )" || true
if printf '%s' "$t3_out" | grep -q '9.9.9'; then
  pass "T3: a fast, healthy row still reports its version through the bounded runner (9.9.9 seen) — the bound refuses hangs, not tools"
else
  fail_ "T3" "the bounded runner lost a healthy row's version; out='$(printf '%s' "$t3_out" | tr '\n' '|' | cut -c1-200)'"
fi

# ── T4: THE BOUND MUST NOT COST A SECOND PER CALL. `run_with_timeout` polls on a
# `sleep 1` counter, so a bounded call pays ~1s even when the command is instant.
# Measured on the real matrix: 21 checkable rows x 2 evals turned a 5-6s script
# into a 50-51s one — inside the SessionStart hook. "A bound exists" and "the
# bound is affordable" are two claims, and the first one shipped alone.
T4="$(newtmp)"
mkdir -p "$T4/templates/tool-matrix" "$T4/.claude"
jq -n '{description:"fixture", schema_version:1, scope:"common",
        tools: ( [range(0;12) | {key:("T"+(.|tostring)),
                 value:{name:("T"+(.|tostring)), category:"mcp_server", phase:2, required:false,
                        check_command:"true", version_command:"echo 1.0.0", description:"fixture"}}]
                 | from_entries )}' > "$T4/templates/tool-matrix/common.json"
t4_start=$(date +%s)
( cd "$T4" && "$BASH_BIN" "$CHECKVER" >/dev/null 2>&1 ) || true
t4_elapsed=$(( $(date +%s) - t4_start ))
if [ "$t4_elapsed" -le 8 ]; then
  pass "T4: 12 instant rows (24 bounded evals) completed in ${t4_elapsed}s — the bound polls a wall-clock deadline, not a 1s-per-call sleep floor that would cost ~24s here and +45s on the shipped matrix"
else
  fail_ "T4" "elapsed ${t4_elapsed}s for 24 evals of instant commands (want <=8s) — the bounded runner is charging ~1s per call, which is +45s inside a SessionStart hook"
fi

echo "=== D — the declaration rows now exercise the tool ==="

# ── D1: the sweep, over EVERY matrix file. No shipped row may decide 'installed'
# by grepping a config file. Derived from the matrices, not from a list here.
d1_files=$(ls "$MATRIX_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')
d1_bad=""
for f in "$MATRIX_DIR"/*.json; do
  d1_hits="$(jq -r --arg f "$(basename "$f")" '.tools | to_entries[]
    | select((.value.check_command // "") | test("jq -e|settings\\.json|[.]claude[.]json"))
    | "  " + $f + ": " + (.value.name // .key)' "$f" 2>/dev/null)"
  [ -n "$d1_hits" ] && d1_bad="$d1_bad
$d1_hits"
done
d1_bad="$(printf '%s' "$d1_bad" | sed '/^$/d')"
if [ -z "$d1_bad" ] && [ "$d1_files" -ge 4 ]; then
  pass "D1: across all $d1_files matrix files, no row decides 'installed' by grepping a config file — the check exercises the tool, which is the difference between configured and working"
else
  fail_ "D1" "files=$d1_files (want >=4; a sweep that reads one file is not a sweep) rows still deciding installed-ness from a config file:
$d1_bad"
fi

# ── D1b: 'a directory exists' and 'an env var is set' are the same substitution
# wearing a different face. Android Studio decided an SDK was present from
# `[ -d ... ] || [ -n "$ANDROID_HOME" ]`, which is true of an empty directory
# and of a stale export.
#
# THE PREDICATE'S OWN WIDTH, stated rather than tuned until green: a `[ -n "$…"`
# branch is flagged unconditionally, because an env-var arm can decide the whole
# check on its own no matter what it is OR-ed with. A `[ -d …` is flagged only
# when nothing in the same check names a concrete artefact — `[ -x`, `[ -f` or
# `command -v`. That let-out is deliberate and it has exactly one live consumer:
# `Development Guardrails for Claude Code` is a cloned repository of shell
# scripts, so `[ -d $HOME/.claude-dev-framework/.git ] && [ -f …/scripts/init.sh ]`
# names a specific file and IS the capability. Narrow this to `[ -x` alone and
# that row goes red for no defect.
d1b_bad=""
for f in "$MATRIX_DIR"/*.json; do
  d1b_hits="$(jq -r --arg f "$(basename "$f")" '.tools[]
    | select((.check_command // "") | test("\\[ -n \"\\$")
             or (test("\\[ -d ") and (test("\\[ -x |\\[ -f |command -v ") | not)))
    | "  " + $f + ": " + (.name // "?") + "  ->  " + (.check_command // "")' "$f" 2>/dev/null)"
  [ -n "$d1b_hits" ] && d1b_bad="$d1b_bad
$d1b_hits"
done
d1b_bad="$(printf '%s' "$d1b_bad" | sed '/^$/d')"
if [ -z "$d1b_bad" ]; then
  pass "D1b: no row decides installed-ness from a bare directory test or a set environment variable without also requiring an executable — a set \$ANDROID_HOME is a declaration, and an empty SDK directory is one too"
else
  fail_ "D1b" "rows deciding installed-ness from a path or an env var alone:
$d1b_bad"
fi

# ── D2: a version that cannot be wrong carries no information. `echo
# 'configured'` is true of a machine with nothing installed. Every matrix file.
d2_bad=""
for f in "$MATRIX_DIR"/*.json; do
  d2_hits="$(jq -r --arg f "$(basename "$f")" '.tools | to_entries[]
    | select((.value.version_command // "") | test("^echo "))
    | "  " + $f + ": " + (.value.name // .key) + "  ->  " + (.value.version_command // "")' "$f" 2>/dev/null)"
  [ -n "$d2_hits" ] && d2_bad="$d2_bad
$d2_hits"
done
d2_bad="$(printf '%s' "$d2_bad" | sed '/^$/d')"
if [ -z "$d2_bad" ] && [ "$d1_files" -ge 4 ]; then
  pass "D2: across all $d1_files matrix files, no row reports a hardcoded version string — a value that cannot be wrong is not evidence, and a tool with genuinely no version now OMITS version_command rather than inventing one"
else
  fail_ "D2" "files=$d1_files (want >=4) rows whose version_command cannot be wrong:
$d2_bad"
fi

echo "=== D — the three-state probe contract, asserted by EQUALITY ==="

if ! start_stub; then
  skip_ "D5-D12, C1, M2-M4" "python3 is unavailable, or the loopback stub server did not bind — the probe's reachability states cannot be exercised without one"
fi

# ── D3: CONFIGURED BUT UNREACHABLE is exactly 2. Not "non-zero": `-ne 0` also
# passes on 127 (the probe was never found) and on a mutant that collapses 2
# into 1, which is how the CWD regression went unseen.
D3="$(newtmp)"; mk_qdrant_home "$D3/home" "http://127.0.0.1:59999"
d3_rc="$(probe_rc "$D3/home" "$REPO_ROOT" qdrant)"
if [ "$d3_rc" -eq 2 ]; then
  pass "D3: MCP config present, nothing listening — rc=2 CANNOT CONFIRM, not 0 and not 1. 'registered' stopped meaning 'working', and 'unreachable' did not become 'absent'"
else
  fail_ "D3" "rc=$d3_rc (want exactly 2). 0 = still reading a declaration; 1 = a reachability failure collapsed into 'not configured'; 127 = the probe script was not found from this CWD"
fi

# ── D4: NOT CONFIGURED is exactly 1.
D4="$(newtmp)"; mkdir -p "$D4/home"; printf '{}\n' > "$D4/home/.claude.json"
d4_rc="$(probe_rc "$D4/home" "$REPO_ROOT" qdrant)"
if [ "$d4_rc" -eq 1 ]; then
  pass "D4: no mcpServers entry at all — rc=1 NOT CONFIGURED. The state below 'cannot confirm' has its own code, so a caller can tell 'you never set this up' from 'it is down'"
else
  fail_ "D4" "rc=$d4_rc (want exactly 1)"
fi

if [ -n "$STUB_PORT" ]; then
STUB="http://127.0.0.1:$STUB_PORT"

# ── D5: WORKING is exactly 0, and only against a real answer.
D5="$(newtmp)"; mk_qdrant_home "$D5/home" "$STUB/qdrant"
d5_rc="$(probe_rc "$D5/home" "$REPO_ROOT" qdrant)"
if [ "$d5_rc" -eq 0 ]; then
  pass "D5: a database that answers with a Qdrant VersionInfo payload — rc=0 WORKING. The positive state is measured too; a probe that can only ever fail proves nothing"
else
  fail_ "D5" "rc=$d5_rc (want exactly 0) against a live stub serving {title, version}"
fi

# ── D6: a 200 from something that is not Qdrant is not evidence of Qdrant. The
# probe's own comment said so and then tested `.version` alone — which a stub
# literally named `totally-not-qdrant` satisfies. `title` is REQUIRED in
# Qdrant's VersionInfo schema (api.qdrant.tech, GET /), so requiring it is the
# published contract rather than a heuristic.
D6="$(newtmp)"; mk_qdrant_home "$D6/home" "$STUB/notqdrant"
d6_rc="$(probe_rc "$D6/home" "$REPO_ROOT" qdrant)"
if [ "$d6_rc" -eq 2 ]; then
  pass "D6: a 200 carrying {name, version} but no 'title' scores 2, not 0 — the payload is checked against Qdrant's own required VersionInfo fields rather than for any '.version' whatsoever"
else
  fail_ "D6" "rc=$d6_rc (want exactly 2) — a service named 'totally-not-qdrant' was accepted as Qdrant"
fi

# ── D7: `.version` as an OBJECT is the Elasticsearch shape. jq's `.version //
# empty` yields a non-empty object, so an emptiness test passes on it.
D7="$(newtmp)"; mk_qdrant_home "$D7/home" "$STUB/esshape"
d7_rc="$(probe_rc "$D7/home" "$REPO_ROOT" qdrant)"
if [ "$d7_rc" -eq 2 ]; then
  pass "D7: a payload whose '.version' is an OBJECT scores 2 — the probe requires a version STRING, so an Elasticsearch-shaped answer cannot pass as a Qdrant one"
else
  fail_ "D7" "rc=$d7_rc (want exactly 2) — '.version' as an object was read as a version"
fi

# ── D8: an api-key-protected database is WORKING, not missing. Qdrant's GET /
# takes an `api-key` header (qdrant.tech/documentation/security); without it a
# secured instance answers 403 and `curl -fsS` reports a failure that is
# indistinguishable from a refused connection.
D8="$(newtmp)"; mk_qdrant_home "$D8/home" "$STUB/authed" "s3cr3t"
d8_rc="$(probe_rc "$D8/home" "$REPO_ROOT" qdrant)"
if [ "$d8_rc" -eq 0 ]; then
  pass "D8: a database behind an api-key, with QDRANT_API_KEY beside QDRANT_URL in the same MCP entry — rc=0. The probe sends the key the operator already configured instead of reporting a healthy database as down"
else
  fail_ "D8" "rc=$d8_rc (want exactly 0) — an api-key-protected Qdrant is being reported as not working"
fi

# ── D9: and when the key is absent, the operator must be told WHICH of the two
# things happened. 'it refused my request' and 'it did not answer at all' are
# different repairs.
D9="$(newtmp)"; mk_qdrant_home "$D9/home" "$STUB/authed"
d9_rc=0
d9_note="$( cd "$REPO_ROOT" && HOME="$D9/home" "$BASH_BIN" "$PROBE" qdrant 2>&1 >/dev/null )" || d9_rc=$?
if [ "$d9_rc" -eq 2 ] && printf '%s' "$d9_note" | grep -q 'HTTP 403'; then
  pass "D9: a secured database with no key configured is rc=2 AND the note names the HTTP status (403) — 'answered and refused me' is reported as itself, not as 'the database did not answer'"
else
  fail_ "D9" "rc=$d9_rc (want 2) note='$(printf '%s' "$d9_note" | tr '\n' '|' | cut -c1-200)' (want it to name HTTP 403)"
fi

# ── D10: the version reported under a row named `Qdrant MCP` must be about the
# MCP SERVER, which `update_check.runner: uvx` names as mcp-server-qdrant — not
# about the DATABASE. A constant that could not be wrong was first replaced by a
# number about a different artifact, which is the same substitution one field
# over.
D10="$(newtmp)"; mk_qdrant_home "$D10/home" "$STUB/dbnine"
mkdir -p "$D10/bin" "$D10/uvcache/archive-v0/abc123/mcp_server_qdrant-1.2.3.dist-info"
printf '#!/bin/sh\n[ "$1" = "cache" ] && [ "$2" = "dir" ] && { echo "%s/uvcache"; exit 0; }\nexit 1\n' "$D10" > "$D10/bin/uv"
chmod +x "$D10/bin/uv"
d10_out="$( cd "$REPO_ROOT" && HOME="$D10/home" PATH="$D10/bin:$PATH" PROBE_QUIET=1 "$BASH_BIN" "$PROBE" qdrant --version 2>/dev/null )" || true
if [ "$d10_out" = "1.2.3" ]; then
  pass "D10: --version reports 1.2.3, the cached mcp-server-qdrant package the uvx runner would launch — not 9.9.9, the version of the DATABASE the same probe just talked to"
else
  fail_ "D10" "printed '$d10_out' (want '1.2.3'); '9.9.9' means the database's version is being reported under the MCP server's name"
fi

# ── D11: and when the package version cannot be established, print NOTHING.
# Absence is honest; the database's number is not a substitute for it.
D11="$(newtmp)"; mk_qdrant_home "$D11/home" "$STUB/dbnine"
mkdir -p "$D11/bin" "$D11/nocache"; printf '#!/bin/sh\nexit 1\n' > "$D11/bin/uv"; chmod +x "$D11/bin/uv"
# UV_CACHE_DIR is pointed at an EMPTY directory, not left to default. The
# fallback when `uv cache dir` fails is the real cache, and this developer's
# machine genuinely has mcp_server_qdrant cached there — so without this the
# case would read 0.8.1 off the host and fail for a reason unrelated to it.
d11_out="$( cd "$REPO_ROOT" && HOME="$D11/home" UV_CACHE_DIR="$D11/nocache" PATH="$D11/bin:$PATH" PROBE_QUIET=1 "$BASH_BIN" "$PROBE" qdrant --version 2>/dev/null )" || true
if [ -z "$d11_out" ]; then
  pass "D11: with no uv cache to read, --version prints nothing at all — an empty version is honest, and check-versions.sh already renders that state"
else
  fail_ "D11" "printed '$d11_out' with no package version obtainable (want empty)"
fi

# ── D12: context7 has a documented HTTP transport with NO `command` field. A
# probe hardcoding `command -v npx` judges such an install by a launcher its
# configuration never mentions.
D12="$(newtmp)"; mkdir -p "$D12/home" "$D12/emptybin"
jq -n --arg u "$STUB/ctx7/" '{mcpServers:{context7:{type:"http", url:$u}}}' > "$D12/home/.claude.json"
d12_rc=0
( cd "$REPO_ROOT" && HOME="$D12/home" PATH="$D12/emptybin:/usr/bin:/bin" PROBE_QUIET=1 "$BASH_BIN" "$PROBE" context7 >/dev/null 2>&1 ) || d12_rc=$?
if [ "$d12_rc" -eq 0 ]; then
  pass "D12: an HTTP-transport context7 entry is probed by FETCHING ITS URL — rc=0 with npx absent from PATH entirely, because npx is not what that configuration runs"
else
  fail_ "D12" "rc=$d12_rc (want 0) — an HTTP-transport context7 is judged by whether npx exists, which its config never mentions"
fi

fi  # stub available

# ── D13: probe_superpowers must select the registry entry by PREDICATE, not by
# position. A stale entry sitting first made a healthy install score 2 and made
# the printed version the wrong one.
D13="$(newtmp)"; mkdir -p "$D13/home/.claude/plugins" "$D13/real/superpowers"
jq -n '{enabledPlugins:{"superpowers@claude-plugins-official":true}}' > "$D13/home/.claude/settings.json"
jq -n --arg p "$D13/real/superpowers" \
  '{plugins:{"superpowers@claude-plugins-official":[
      {installPath:"/nonexistent/stale/6.0.0", version:"6.0.0"},
      {installPath:$p, version:"6.3.0"}]}}' > "$D13/home/.claude/plugins/installed_plugins.json"
d13_rc="$(probe_rc "$D13/home" "$REPO_ROOT" superpowers)"
d13_ver="$( cd "$REPO_ROOT" && HOME="$D13/home" PROBE_QUIET=1 "$BASH_BIN" "$PROBE" superpowers --version 2>/dev/null )" || true
if [ "$d13_rc" -eq 0 ] && [ "$d13_ver" = "6.3.0" ]; then
  pass "D13: with a stale registry entry FIRST and the real install second, the probe scores 0 and prints 6.3.0 — the entry is chosen by whether its installPath exists, not by sitting at index [0]"
else
  fail_ "D13" "rc=$d13_rc (want 0) version='$d13_ver' (want 6.3.0) — [0]-by-position false-alarms against a healthy install and prints the wrong version"
fi

# ── D14: and a registry in which NO recorded path exists is still 2. Fixing the
# selection must not turn 'cannot confirm' into 'working'.
D14="$(newtmp)"; mkdir -p "$D14/home/.claude/plugins"
jq -n '{enabledPlugins:{"superpowers@claude-plugins-official":true}}' > "$D14/home/.claude/settings.json"
jq -n '{plugins:{"superpowers@claude-plugins-official":[
      {installPath:"/nonexistent/a", version:"6.0.0"},
      {installPath:"/nonexistent/b", version:"6.3.0"}]}}' > "$D14/home/.claude/plugins/installed_plugins.json"
d14_rc="$(probe_rc "$D14/home" "$REPO_ROOT" superpowers)"
if [ "$d14_rc" -eq 2 ]; then
  pass "D14: enabled, registry present, but no recorded installPath exists on disk — still rc=2. Selecting by predicate did not soften the third state into the first"
else
  fail_ "D14" "rc=$d14_rc (want exactly 2)"
fi

echo "=== C — measured where a CONSUMER reads the answer ==="

# ── C1: THE ROW MUST NOT DEPEND ON `pwd`. `bash scripts/probe-tool.sh` resolves
# only from the repo root; a consumer invoked from anywhere else gets rc=127 and
# reads it as 'not installed'. init.sh runs the resolver before any `cd`, so
# this is reachable by the ordinary `init.sh --project-dir` invocation. Measured
# at the consumer, from a directory that is NOT the repo root, against the
# SHIPPED row rather than a fixture copy of it.
if [ -z "$STUB_PORT" ]; then
  skip_ "C1" "no stub server — this case needs a database that WOULD answer, or 'not installed' is the right answer for the wrong reason"
else
  C1="$(newtmp)"; mk_shipped_row_proj "$C1" "Qdrant MCP"
  mk_qdrant_home "$C1/home" "http://127.0.0.1:$STUB_PORT/qdrant"
  c1_out="$( cd "$C1" && HOME="$C1/home" "$BASH_BIN" "$CHECKVER" 2>&1 )" || true
  if printf '%s' "$c1_out" | grep -q 'Qdrant MCP' && ! printf '%s' "$c1_out" | grep -q 'Qdrant MCP: not installed'; then
    pass "C1: run from a project directory that is not the repo root, with a database that answers, check-versions.sh reports the Qdrant row as present — the row locates the probe itself instead of trusting the caller's pwd"
  else
    fail_ "C1" "out='$(printf '%s' "$c1_out" | tr '\n' '|' | cut -c1-300)' — a working database read as 'not installed' from a non-root CWD is rc=127 wearing the costume of a real answer"
  fi
fi

# ── C2: the constant must not survive by MOVING FILE. D2 asserts on matrix JSON
# and cannot see `${INSTALLED:-configured}` inside check-versions.sh, which
# renders the same word for exactly the same rows.
C2="$(newtmp)"; mk_matrix_proj "$C2" 'true' 'true'
c2_out="$( cd "$C2" && "$BASH_BIN" "$CHECKVER" 2>&1 )" || true
if printf '%s' "$c2_out" | grep -q 'Probe' && ! printf '%s' "$c2_out" | grep -qi 'configured'; then
  pass "C2: a row that passes its check but reports no version renders WITHOUT the word 'configured' — the constant this entry exists to delete is gone from the rendered OUTPUT, not just from the data file"
else
  fail_ "C2" "out='$(printf '%s' "$c2_out" | tr '\n' '|' | cut -c1-300)' — the word 'configured' is still rendered, or the row vanished entirely"
fi

# ── C3: THE DIAGNOSIS MUST REACH THE OPERATOR, NOT JUST THE PROBE'S STDERR.
#
# D9 asserts that a secured-but-unkeyed database produces a note naming HTTP
# 403 — and asserts it ON THE PROBE. check-versions.sh then ran the check as
# `>/dev/null 2>&1`, so all three states arrived as one word: a database that is
# UP and refusing for want of a key rendered identically to one that was never
# installed. That is this entry's own defect, one layer out, and D9 could not
# see it because D9 stops where the answer is PRODUCED rather than where it is
# CONSUMED. This case reads the rendered report.
if [ -z "$STUB_PORT" ]; then
  skip_ "C3" "no stub server — the 403 path needs a database that answers and refuses"
else
  C3="$(newtmp)"; mk_shipped_row_proj "$C3" "Qdrant MCP"
  mk_qdrant_home "$C3/home" "http://127.0.0.1:$STUB_PORT/authed"   # key deliberately absent
  c3_out="$( cd "$C3" && HOME="$C3/home" "$BASH_BIN" "$CHECKVER" 2>&1 )" || true
  if printf '%s' "$c3_out" | grep -q 'HTTP 403' \
     && printf '%s' "$c3_out" | grep -q 'QDRANT_API_KEY' \
     && ! printf '%s' "$c3_out" | grep -q 'Qdrant MCP: not installed'; then
    pass "C3: a running database refusing an unkeyed probe is reported BY check-versions.sh as HTTP 403 with the QDRANT_API_KEY repair — the third state and its diagnosis survive the trip to the operator instead of being flattened to 'not installed'"
  else
    fail_ "C3" "out='$(printf '%s' "$c3_out" | tr '\n' '|' | cut -c1-300)' — wanted the 403 and the QDRANT_API_KEY guidance, and NOT 'not installed' for a database that is up"
  fi
fi

# ── C4: A TOOL'S STDERR MUST NOT BE ABLE TO FORGE A REPORT LINE.
#
# Surfacing the note (C3) handed a tool's stderr straight to `print_warn`, which
# renders through `echo -e` — and `echo -e` INTERPRETS backslash escapes. A note
# containing the two characters `\` and `n` therefore becomes a real line break,
# and whatever follows it starts a new line of the report. Measured before the
# fix, from a check_command whose stderr was
# `note-one\nFORGED  [OK] Totally Installed: 9.9.9`:
#
#     [WARN] P: configured, but working could not be confirmed — note-one
#     FORGED  [OK] Totally Installed: 9.9.9
#
# — a fabricated `[OK]` row, in the one script whose whole job is reporting
# honestly. The rows ship with the framework, but the probe notes interpolate
# `$(qdrant_mcp_url)` read from `~/.claude.json`, so the text is not all ours.
# This is the cost of C3's fix and it is paid here rather than left standing.
C4="$(newtmp)"
mk_matrix_proj "$C4" 'printf %s "note-one\nFORGED  [OK] Totally Installed: 9.9.9" >&2; exit 2' 'echo 1'
c4_out="$( cd "$C4" && "$BASH_BIN" "$CHECKVER" 2>&1 )" || true
c4_forged=$(_num "$(printf '%s' "$c4_out" | grep -c '^FORGED')")
c4_kept=$(_num "$(printf '%s' "$c4_out" | grep -c 'note-one')")
if [ "$c4_forged" -eq 0 ] && [ "$c4_kept" -ge 1 ]; then
  pass "C4: a note carrying a literal backslash-n is rendered as text, not as a line break — the note still reaches the operator (note-one seen) but cannot start a new line, so a tool's stderr cannot forge an [OK] row"
else
  fail_ "C4" "lines beginning FORGED=$c4_forged (want 0) note-present=$c4_kept (want >=1) — out='$(printf '%s' "$c4_out" | tr '\n' '|' | cut -c1-300)'"
fi

echo "=== X — the resolver is EXECUTED, so its mode is part of its contract ==="

# ── X1: `scripts/resolve-tools.sh` must be executable.
#
# THIS IS NOT HYGIENE, IT IS THIS ENTRY'S OWN DEFECT CLASS — and the four
# callers do NOT behave alike, which an earlier version of this comment got
# wrong by asserting they did. Derived, per caller:
#
#   init.sh                 EXECUTES it (`"$SCRIPT_DIR/scripts/resolve-tools.sh" …`)
#                           -> rc=126 -> `|| { print_warn "Tool resolver
#                           failed. Falling back to basic tool checks."; return 0; }`
#   verify-install.sh       gated `[ ! -x … ] -> register_manual "Tool check
#                           skipped …"; return`, and the call itself carries a
#                           `bash ` prefix, so the mode never reaches execve
#   intake-wizard.sh        gated `[ -x … ] && …` -> the block is SKIPPED
#   check-phase-gate.sh     gated `[ -x "$RESOLVER" ]` -> the block is SKIPPED
#
# So exactly ONE caller produces 126 and the other three degrade by SILENT SKIP
# — the worse arm, not the milder one: init.sh at least prints a warning. That
# is also why "the shell will tell you" does not justify skipping this check.
# Measured, because it happened during this very fix: an editor of mine wrote
# the file through `sed > tmp && mv`, which silently replaced 755 with 644, and
# the only visible trace was one `[WARN]` line and three context values that had
# acquired a leading space. A green suite, a zero exit code, and a wrong project.
#
# `bash tests/foo.sh` is how tests are run, so test files are exempt by
# construction; this asserts the mode only where something executes the file.
x1_mode="$(_mode_of "$REPO_ROOT/scripts/resolve-tools.sh")"
if [ -x "$REPO_ROOT/scripts/resolve-tools.sh" ]; then
  pass "X1: scripts/resolve-tools.sh is executable (mode $x1_mode) — its four callers invoke it directly, and losing the bit turns 'the tool matrix was resolved' into a WARN that still exits 0"
else
  fail_ "X1" "mode=$x1_mode — resolve-tools.sh is not executable, so every direct caller gets rc=126 and init.sh silently falls back to basic tool checks while still reporting success"
fi

echo "=== M — mutation proofs ==="

# ── M1: remove the bound and T1 must hang again.
M1="$(newtmp)"; cp -R "$REPO_ROOT/scripts" "$M1/scripts" 2>/dev/null
m1_meta=$(_mutate "$M1/scripts/check-versions.sh" '# BL-235-BOUND-CHECK' '  eval "$CHECK_CMD" >/dev/null 2>"$CHECK_ERR" || CHECK_RC=$?')
m1_sites="${m1_meta%% *}"; m1_rest="${m1_meta#* }"; m1_changed="${m1_rest%% *}"; m1_parses="${m1_rest##* }"
# 6s, not 12s: the discrimination is "returns at the 2s bound" vs "runs to
# completion", and 6 separates those as cleanly as 12 for half the wall clock.
# This suite is pinned to a CI shard, so its own duration is a cost.
M1D="$(newtmp)"; mk_matrix_proj "$M1D" 'sleep 6' "echo 1.0"
m1_start=$(date +%s)
( cd "$M1D" && "$BASH_BIN" "$M1/scripts/check-versions.sh" >/dev/null 2>&1 ) || true
m1_elapsed=$(( $(date +%s) - m1_start ))
if [ "$m1_sites" -eq 1 ] && [ "$m1_parses" -eq 1 ] && [ "$m1_elapsed" -ge 5 ]; then
  pass "M1: with the bound removed, a 6s check_command holds the script for ${m1_elapsed}s again — the bound is load-bearing and measured in seconds, not asserted (sites=$m1_sites changed=$m1_changed parses=$m1_parses)"
else
  fail_ "M1" "sites=$m1_sites (want 1) parses=$m1_parses (want 1) changed=$m1_changed elapsed=${m1_elapsed}s (want >=5)"
fi

# ── M2: put the rows back to a CWD-relative path and C1's condition must return.
if [ -n "$STUB_PORT" ]; then
  M2="$(newtmp)"; cp -R "$MATRIX_DIR" "$M2/tool-matrix"
  m2_meta=$(_mutate_json "$M2/tool-matrix/common.json" \
    '.tools |= map(if (.check_command // "") | test("probe-tool") then .check_command = "bash scripts/probe-tool.sh qdrant" else . end)')
  m2_changed="${m2_meta%% *}"; m2_parses="${m2_meta##* }"
  M2D="$(newtmp)"; mkdir -p "$M2D/templates" "$M2D/home"
  cp -R "$M2/tool-matrix" "$M2D/templates/tool-matrix"
  mk_qdrant_home "$M2D/home" "http://127.0.0.1:$STUB_PORT/qdrant"
  m2_chk="$(jq -r '.tools | to_entries[] | select(.value.name == "Qdrant MCP") | .value.check_command' "$M2D/templates/tool-matrix/common.json")"
  m2_rc=0
  ( cd "$M2D" && HOME="$M2D/home" SOLO_SCRIPTS_DIR="$REPO_ROOT/scripts" "$BASH_BIN" -c "$m2_chk" >/dev/null 2>&1 ) || m2_rc=$?
  if [ "$m2_changed" -ge 2 ] && [ "$m2_parses" -eq 1 ] && [ "$m2_rc" -eq 127 ]; then
    pass "M2: reverted to 'bash scripts/probe-tool.sh', the row returns rc=127 from a non-root CWD even with SOLO_SCRIPTS_DIR exported — the fix lives in the row, and its absence is visible as the command-not-found it really is (changed=$m2_changed parses=$m2_parses)"
  else
    fail_ "M2" "changed=$m2_changed (want >=2) parses=$m2_parses (want 1) rc=$m2_rc (want 127)"
  fi
fi

# ── M3: drop the `title` requirement and D6 must accept `totally-not-qdrant`.
if [ -n "$STUB_PORT" ]; then
  M3="$(newtmp)"; cp -R "$REPO_ROOT/scripts" "$M3/scripts"
  m3_meta=$(_mutate "$M3/scripts/probe-tool.sh" '# BL-235-PROBE-IDENTITY' \
    '  ver="$(printf %s "$payload" | jq -r ".version // empty" 2>/dev/null)"; title="x"')
  m3_sites="${m3_meta%% *}"; m3_rest="${m3_meta#* }"; m3_changed="${m3_rest%% *}"; m3_parses="${m3_rest##* }"
  M3H="$(newtmp)"; mk_qdrant_home "$M3H/home" "http://127.0.0.1:$STUB_PORT/notqdrant"
  m3_rc=0
  ( cd "$REPO_ROOT" && HOME="$M3H/home" PROBE_QUIET=1 "$BASH_BIN" "$M3/scripts/probe-tool.sh" qdrant >/dev/null 2>&1 ) || m3_rc=$?
  if [ "$m3_sites" -ge 1 ] && [ "$m3_parses" -eq 1 ] && [ "$m3_rc" -eq 0 ]; then
    pass "M3: with the identity check reduced to '.version // empty', a stub named totally-not-qdrant scores 0 again — D6 is discriminating, not decorative (sites=$m3_sites changed=$m3_changed)"
  else
    fail_ "M3" "sites=$m3_sites (want >=1) parses=$m3_parses (want 1) rc=$m3_rc (want 0)"
  fi
fi

# ── M4: drop the api-key read and D8's protected database goes dark again.
# THE MARKER IS IN helpers-full.sh, NOT IN THE PROBE. Everything credential-
# shaped for Qdrant has one owner there — which file the entry is read from,
# that the URL and key come from the SAME entry, that the key travels only to a
# declared host, and that it never reaches argv. A first draft of this case
# mutated probe-tool.sh, found zero sites, and reported a mutation proof that
# proved nothing.
if [ -n "$STUB_PORT" ]; then
  M4="$(newtmp)"; cp -R "$REPO_ROOT/scripts" "$M4/scripts"
  m4_meta=$(_mutate "$M4/scripts/lib/helpers-full.sh" '# BL-235-ROOT-KEY-HEADER' '  key=""')
  m4_sites="${m4_meta%% *}"; m4_rest="${m4_meta#* }"; m4_changed="${m4_rest%% *}"; m4_parses="${m4_rest##* }"
  M4H="$(newtmp)"; mk_qdrant_home "$M4H/home" "http://127.0.0.1:$STUB_PORT/authed" "s3cr3t"
  m4_rc=0
  ( cd "$REPO_ROOT" && HOME="$M4H/home" PROBE_QUIET=1 "$BASH_BIN" "$M4/scripts/probe-tool.sh" qdrant >/dev/null 2>&1 ) || m4_rc=$?
  if [ "$m4_sites" -ge 1 ] && [ "$m4_parses" -eq 1 ] && [ "$m4_rc" -eq 2 ]; then
    pass "M4: with the configured api-key discarded, the healthy secured database scores 2 again — D8 measures the header, not the happy path (sites=$m4_sites changed=$m4_changed)"
  else
    fail_ "M4" "sites=$m4_sites (want >=1) parses=$m4_parses (want 1) rc=$m4_rc (want 2)"
  fi
fi

# ── M5: restore [0]-by-position and D13's healthy install false-alarms again.
# The mutant TRUNCATES the candidate list to its first row and leaves the
# on-disk test in place — which is exactly what `.plugins[<id>][0].installPath`
# did. A first draft replaced the FUNCTION HEADER (the marker had been parked
# there), so the mutant did not parse and `parses=0` reported the case as
# broken rather than as proof. A mutant that fails to parse kills nothing.
M5="$(newtmp)"; cp -R "$REPO_ROOT/scripts" "$M5/scripts"
m5_meta=$(_mutate "$M5/scripts/probe-tool.sh" '# BL-235-PROBE-PLUGIN-SELECT' \
  '  rows="$(printf "%s\\n" "$rows" | head -1)"; while IFS=$'"'"'\t'"'"' read -r path ver; do')
m5_sites="${m5_meta%% *}"; m5_rest="${m5_meta#* }"; m5_changed="${m5_rest%% *}"; m5_parses="${m5_rest##* }"
m5_rc=0
( cd "$REPO_ROOT" && HOME="$D13/home" PROBE_QUIET=1 "$BASH_BIN" "$M5/scripts/probe-tool.sh" superpowers >/dev/null 2>&1 ) || m5_rc=$?
if [ "$m5_sites" -ge 1 ] && [ "$m5_parses" -eq 1 ] && [ "$m5_rc" -eq 2 ]; then
  pass "M5: with selection back at index [0], the healthy install behind a stale first entry scores 2 again — D13 pins the predicate, not the happy ordering (sites=$m5_sites changed=$m5_changed)"
else
  fail_ "M5" "sites=$m5_sites (want >=1) parses=$m5_parses (want 1) rc=$m5_rc (want 2)"
fi

# ── M6: restore the `configured` fallback and C2 must see the word return.
M6="$(newtmp)"; cp -R "$REPO_ROOT/scripts" "$M6/scripts"
m6_meta=$(_mutate "$M6/scripts/check-versions.sh" '# BL-235-NO-CONSTANT' \
  '  INSTALLED_DISPLAY="${INSTALLED:-configured}"')
m6_sites="${m6_meta%% *}"; m6_rest="${m6_meta#* }"; m6_changed="${m6_rest%% *}"; m6_parses="${m6_rest##* }"
M6D="$(newtmp)"; mk_matrix_proj "$M6D" 'true' 'true'
m6_out="$( cd "$M6D" && "$BASH_BIN" "$M6/scripts/check-versions.sh" 2>&1 )" || true
if [ "$m6_sites" -ge 1 ] && [ "$m6_parses" -eq 1 ] && printf '%s' "$m6_out" | grep -qi 'configured'; then
  pass "M6: with the fallback restored, 'configured' is rendered again for a version-less row — C2 reads the OUTPUT, which is the surface D2 could never see (sites=$m6_sites changed=$m6_changed)"
else
  fail_ "M6" "sites=$m6_sites (want >=1) parses=$m6_parses (want 1) out='$(printf '%s' "$m6_out" | tr '\n' '|' | cut -c1-200)'"
fi

# ── M8: put the version read back on a command substitution and T2b must hang
# again. The mutant is ONE LINE and behaviour-identical for every non-pipeline
# row, which is exactly why the original shipped through a review.
M8="$(newtmp)"; cp -R "$REPO_ROOT/scripts" "$M8/scripts"
m8_meta=$(_mutate "$M8/scripts/check-versions.sh" '# BL-235-BOUND-VERSION' \
  '    INSTALLED=$(_cv_bounded_eval "$VERSION_CMD" 2>/dev/null | tr -d "[:space:]" || echo ""); CV_NOTE=""')
m8_sites="${m8_meta%% *}"; m8_rest="${m8_meta#* }"; m8_changed="${m8_rest%% *}"; m8_parses="${m8_rest##* }"
M8D="$(newtmp)"; mk_matrix_proj "$M8D" 'true' 'sleep 6 | cat'
m8_start=$(date +%s)
( cd "$M8D" && CHECKVER_EVAL_TIMEOUT=2 "$BASH_BIN" "$M8/scripts/check-versions.sh" >/dev/null 2>&1 ) || true
m8_elapsed=$(( $(date +%s) - m8_start ))
if [ "$m8_sites" -eq 1 ] && [ "$m8_parses" -eq 1 ] && [ "$m8_elapsed" -ge 5 ]; then
  pass "M8: with the version read back on a command substitution, a 6s pipeline holds the script for ${m8_elapsed}s against a 2s bound — T2b measures the CONSUMPTION, which is where the bound was being defeated (sites=$m8_sites changed=$m8_changed)"
else
  fail_ "M8" "sites=$m8_sites (want 1) parses=$m8_parses (want 1) changed=$m8_changed elapsed=${m8_elapsed}s (want >=5)"
fi

# ── M9: discard the check's stderr and exit code again, and C3 must lose both
# the status and the repair — the exact line this branch shipped first.
if [ -n "$STUB_PORT" ]; then
  M9="$(newtmp)"; cp -R "$REPO_ROOT/scripts" "$M9/scripts"
  m9_meta=$(_mutate "$M9/scripts/check-versions.sh" '# BL-235-BOUND-CHECK' \
    '  _cv_bounded_eval "$CHECK_CMD" >/dev/null 2>&1 || CHECK_RC=$?')
  m9_sites="${m9_meta%% *}"; m9_rest="${m9_meta#* }"; m9_changed="${m9_rest%% *}"; m9_parses="${m9_rest##* }"
  M9D="$(newtmp)"; mk_shipped_row_proj "$M9D" "Qdrant MCP"
  mk_qdrant_home "$M9D/home" "http://127.0.0.1:$STUB_PORT/authed"
  m9_out="$( cd "$M9D" && HOME="$M9D/home" "$BASH_BIN" "$M9/scripts/check-versions.sh" 2>&1 )" || true
  if [ "$m9_sites" -eq 1 ] && [ "$m9_parses" -eq 1 ] \
     && ! printf '%s' "$m9_out" | grep -q 'HTTP 403'; then
    pass "M9: with the check's stderr discarded again, a live database refusing on 403 loses its status and its repair on the way to the operator — C3 reads the report, which is the only surface this is visible on (sites=$m9_sites changed=$m9_changed)"
  else
    fail_ "M9" "sites=$m9_sites (want 1) parses=$m9_parses (want 1) out='$(printf '%s' "$m9_out" | tr '\n' '|' | cut -c1-200)'"
  fi
fi

# ── M10: a non-numeric bound must not mean ZERO. `$(( now + abc ))` is `now`,
# so an unparseable timeout made every deadline already-past and turned a whole
# healthy matrix into "not installed" — silently, from one environment variable.
M10="$(newtmp)"; mk_matrix_proj "$M10" 'true' "echo 9.9.9"
m10_ctl="$( cd "$M10" && CHECKVER_EVAL_TIMEOUT=abc "$BASH_BIN" "$CHECKVER" 2>&1 )" || true
M10M="$(newtmp)"; cp -R "$REPO_ROOT/scripts" "$M10M/scripts"
m10_meta=$(_mutate "$M10M/scripts/lib/helpers-core.sh" '# BL-235-DEADLINE-SANE' '  :')
m10_sites="${m10_meta%% *}"; m10_rest="${m10_meta#* }"; m10_changed="${m10_rest%% *}"; m10_parses="${m10_rest##* }"
m10_mut="$( cd "$M10" && CHECKVER_EVAL_TIMEOUT=abc "$BASH_BIN" "$M10M/scripts/check-versions.sh" 2>&1 )" || true
m10_c=$(printf '%s' "$m10_ctl" | grep -c '9.9.9'); m10_m=$(printf '%s' "$m10_mut" | grep -c '9.9.9')
if [ "$(_num "$m10_c")" -ge 1 ] && [ "$m10_sites" -eq 1 ] && [ "$m10_parses" -eq 1 ] && [ "$(_num "$m10_m")" -eq 0 ]; then
  pass "M10: CHECKVER_EVAL_TIMEOUT=abc still reports 9.9.9; with the clamp removed the same healthy row vanishes — an unparseable bound makes the deadline equal now, so every row times out instantly and a whole matrix reads as missing from one malformed environment variable (sites=$m10_sites changed=$m10_changed)"
else
  fail_ "M10" "control_hits=$m10_c (want >=1) sites=$m10_sites (want 1) parses=$m10_parses (want 1) mutant_hits=$m10_m (want 0)"
fi

# ── M11: remove the escape-doubling and C4's forged line must come back.
M11="$(newtmp)"; cp -R "$REPO_ROOT/scripts" "$M11/scripts"
m11_meta=$(_mutate "$M11/scripts/check-versions.sh" '# BL-235-NOTE-SAFE' '  printf "%s" "$1"')
m11_sites="${m11_meta%% *}"; m11_rest="${m11_meta#* }"; m11_changed="${m11_rest%% *}"; m11_parses="${m11_rest##* }"
M11D="$(newtmp)"
mk_matrix_proj "$M11D" 'printf %s "note-one\nFORGED  [OK] Totally Installed: 9.9.9" >&2; exit 2' 'echo 1'
m11_out="$( cd "$M11D" && "$BASH_BIN" "$M11/scripts/check-versions.sh" 2>&1 )" || true
m11_forged=$(_num "$(printf '%s' "$m11_out" | grep -c '^FORGED')")
if [ "$m11_sites" -eq 1 ] && [ "$m11_parses" -eq 1 ] && [ "$m11_forged" -ge 1 ]; then
  pass "M11: with the escape-doubling removed, the note's literal backslash-n becomes a real line break again and a fabricated '[OK] Totally Installed' row appears in the report — C4 measures forgery, not merely that a note is printed (sites=$m11_sites changed=$m11_changed)"
else
  fail_ "M11" "sites=$m11_sites (want 1) parses=$m11_parses (want 1) forged_lines=$m11_forged (want >=1)"
fi

# ── M7: X1 must be able to fail. Strip the bit from a COPY and re-run the same
# predicate on it — and confirm the copy's content is byte-identical, so the
# only thing that changed is the mode.
M7="$(newtmp)"; cp "$REPO_ROOT/scripts/resolve-tools.sh" "$M7/resolve-tools.sh"
chmod 644 "$M7/resolve-tools.sh"
m7_same=0; cmp -s "$REPO_ROOT/scripts/resolve-tools.sh" "$M7/resolve-tools.sh" && m7_same=1
m7_x=0; [ -x "$M7/resolve-tools.sh" ] && m7_x=1
m7_rc=0
( cd "$M7" && ./resolve-tools.sh --dev-os darwin --platform web --language typescript \
    --track light --phase 2 --matrix-dir "$MATRIX_DIR" >/dev/null 2>&1 ) || m7_rc=$?
if [ "$m7_same" -eq 1 ] && [ "$m7_x" -eq 0 ] && [ "$m7_rc" -eq 126 ]; then
  pass "M7: a byte-identical copy at mode 644 is refused by the shell with rc=126 — X1 measures the bit, and 126 is exactly what init.sh's resolver call substitution returns before it warns and carries on (content_identical=$m7_same)"
else
  fail_ "M7" "content_identical=$m7_same (want 1) executable=$m7_x (want 0) rc=$m7_rc (want 126)"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

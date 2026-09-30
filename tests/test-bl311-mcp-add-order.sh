#!/usr/bin/env bash
# tests/test-bl311-mcp-add-order.sh — `## BL-311:` no tracked file may print or
# run a `claude mcp add` whose `-e`/`--env` comes before the server name.
#
# WHY. `claude mcp add --help` (Claude Code 2.1.283) declares
# `-e, --env <env...>` — VARIADIC — and its own example puts the name first:
# `claude mcp add my-server -e API_KEY=xxx -- npx my-mcp-server`. Written the
# other way round, `-e QDRANT_URL=… -e COLLECTION_NAME=claude-memory qdrant --`
# takes `qdrant` as a third environment value and exits 1 with "Invalid
# environment variable format: qdrant" (measured against a scratch
# CLAUDE_CONFIG_DIR). The framework shipped that spelling in eleven places —
# init.sh's registration and its hint, register_qdrant_mcp, check-phase-gate.sh,
# the tool matrix and the CLI Setup Addendum — so every Qdrant registration it
# ran failed, and every one it printed failed when pasted.
#
# WHAT IS SCANNED. Every TRACKED file (`git ls-files`), because the set of
# places a command is spelled is exactly what rotted. Backslash-continued lines
# are JOINED first: the Addendum writes the command over four lines, with the
# name on the last, and a line-at-a-time scan cannot see its order at all.
#
# THE PARSE. For each `claude mcp add` on a logical line, the text up to the
# command separator ` -- ` (or the end of the command: a quote, a backtick, a
# `;`, `|`, `&`, `)` or `>`) is split into words. Options that take ONE value
# (`-s/--scope`, `-t/--transport`, `--callback-port`, `--client-id`) skip it; the
# first word that is not an option is the server name. A `-e`/`--env` — or the
# other variadic, `-H`/`--header`, which fails the same way — met BEFORE the name
# is the defect. A `claude mcp add` with no `-e` at all (Context7's) is fine.
#
# TWO FILES ARE ALLOWED TO SPELL THE DEFECT, EACH FOR A STATED REASON (below):
# this suite's own fixtures, and tests/test-bl311-adopt-mcp-mutants.sh's M12, which
# reintroduces the broken order on purpose to prove the adoption step's guard.
#
# Cases: O1 the tracked tree is clean; O2-O5 the parser's positive and negative
# controls (single-line, the Addendum's continued form, `--env`, the
# Context7/name-first forms); OM1/OM2 mutation proofs — a broken copy put back
# into a mirrored real file, one single-line and one continued, must be found.
# P1-P3/PM1-PM2 do the same for the second copied-everywhere defect: the Qdrant
# container's ports must be published on 127.0.0.1, not on every interface.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

echo "== BL-311 — claude mcp add puts the server name before -e =="
WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK"' EXIT

# THE ALLOWLIST. Path, then the reason it may spell the broken order.
ALLOW_PATHS="
tests/test-bl311-mcp-add-order.sh
tests/test-bl311-adopt-mcp-mutants.sh
"
# tests/test-bl311-mcp-add-order.sh — its O2-O5 fixtures and OM1/OM2 mutants
#   must contain the defect to prove the scanner finds it.
# tests/test-bl311-adopt-mcp-mutants.sh — its M12 mutant writes the broken order back
#   into adopt-mcp.sh to prove the adoption step's guard (`# BL-311-MCP-QDRANT-ADD`).

# _scan FILE... — print `file:line: <the offending command>` for each defect.
# The line number is the logical line's FIRST physical line.
_scan() {
  LC_ALL=C awk '
    function report(txt, n,   rest, i, seg, j, c, cut, k, w, nw, name, bad, t) {
      rest = txt
      while ((i = index(rest, "claude mcp add")) > 0) {
        seg = substr(rest, i + 14)
        rest = seg
        c = substr(seg, 1, 1)
        if (c != "" && c != " " && c != "\t") continue           # add-json and the like
        cut = index(seg, " -- "); if (cut > 0) seg = substr(seg, 1, cut - 1)
        for (j = 1; j <= length(seg); j++) {
          c = substr(seg, j, 1)
          if (c == "\"" || c == "\047" || c == "`" || c == ";" || c == "|" || c == "&" || c == ")" || c == ">") { seg = substr(seg, 1, j - 1); break }
        }
        nw = split(seg, w, /[ \t]+/)
        name = ""; bad = 0
        for (k = 1; k <= nw; k++) {
          t = w[k]
          if (t == "") continue
          if (t == "-s" || t == "--scope" || t == "-t" || t == "--transport" || t == "--callback-port" || t == "--client-id") { k++; continue }
          if (t ~ /^--(scope|transport|callback-port|client-id)=/) continue
          if (t == "-e" || t == "--env" || t ~ /^--env=/ || t ~ /^-e./ || t == "-H" || t == "--header" || t ~ /^--header=/) { bad = 1; break }
          if (t ~ /^-/) continue
          name = t; break
        }
        if (bad) printf "%s:%d: claude mcp add%s\n", FILENAME, n, substr(txt, index(txt, "claude mcp add") + 14, 120)
      }
    }
    FNR == 1 { buf = ""; start = 0 }
    {
      line = $0
      if (buf == "") start = FNR
      if (line ~ /\\$/) { buf = buf substr(line, 1, length(line) - 1) " "; next }
      buf = buf line
      report(buf, start)
      buf = ""
    }
    END { }
  ' "$@"
}

# _tracked_hits ROOT — tracked files under ROOT that mention the command at all,
# minus the allowlist.
_tracked_hits() {
  local root="$1" f=""
  ( cd "$root" && git ls-files ) | while IFS= read -r f; do
    [ -f "$root/$f" ] || continue
    case "$ALLOW_PATHS" in *"
$f
"*) continue ;; esac
    command grep -l 'claude mcp add' "$root/$f" 2>/dev/null
  done
}

# ── O1 — the tracked tree ───────────────────────────────────────────────────
_tracked_hits "$REPO_ROOT" > "$WORK/files"
o1_files=$(command grep -c . "$WORK/files")
if [ "$o1_files" -gt 0 ]; then
  ( while IFS= read -r f; do _scan "$f"; done < "$WORK/files" ) > "$WORK/o1"
  if [ -s "$WORK/o1" ]; then
    sed "s#$REPO_ROOT/##; s#^#         (O1) #" "$WORK/o1" | cut -c1-160
    fail_ "O1 the tracked tree" "$(command grep -c . "$WORK/o1") broken spelling(s), listed above — put the server name before -e"
  else
    pass "O1 no tracked file spells a claude mcp add with -e before the server name ($o1_files file(s) mention the command; the allowlist is this suite and test-bl311-adopt-mcp-mutants.sh)"
  fi
else
  fail_ "O1 the tracked tree" "no tracked file mentions 'claude mcp add' — the scan cannot be looking at the repository"
fi

# ── O2-O5 — the parser, both directions ─────────────────────────────────────
cat > "$WORK/broken-single.sh" <<'FIX'
if run_with_timeout 30 bash -c 'echo "y" | claude mcp add -s user -e QDRANT_URL=http://localhost:6333 -e COLLECTION_NAME=claude-memory qdrant -- uvx --python 3.13 mcp-server-qdrant >/dev/null 2>&1'; then
FIX
cat > "$WORK/broken-continued.md" <<'FIX'
```bash
claude mcp add -s user \
  -e QDRANT_URL=http://localhost:6333 \
  -e COLLECTION_NAME=claude-memory \
  qdrant -- uvx --python 3.13 mcp-server-qdrant
```
FIX
cat > "$WORK/broken-env.json" <<'FIX'
{"manual": "Setup: (2) claude mcp add --scope user --env QDRANT_URL=http://localhost:6333 qdrant -- uvx mcp-server-qdrant"}
FIX
cat > "$WORK/fine.md" <<'FIX'
claude mcp add -s user qdrant -e QDRANT_URL=http://localhost:6333 -e COLLECTION_NAME=claude-memory -- uvx --python 3.13 mcp-server-qdrant
claude mcp add -s user qdrant \
  -e QDRANT_URL=http://localhost:6333 \
  -- uvx --python 3.13 mcp-server-qdrant
claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp
- [ ] Context7 MCP added (`claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp`)
the fix is `claude mcp add`, and `claude mcp add -s user …` wrote the file
claude mcp add-json qdrant '{"env":{}}'
FIX
o2="$(_scan "$WORK/broken-single.sh" | command grep -c .)"
[ "$o2" = 1 ] && pass "O2 a single-line registration with -e before the name is found" || fail_ "O2" "found $o2 (want 1)"
o3="$(_scan "$WORK/broken-continued.md")"
if [ "$(printf '%s\n' "$o3" | command grep -c .)" = 1 ] && printf '%s' "$o3" | command grep -q 'broken-continued.md:2:'; then
  pass "O3 the Addendum's backslash-continued form, name on the last line, is found (and reported at its first line)"
else fail_ "O3" "got '$o3' (want one hit at line 2)"; fi
o4="$(_scan "$WORK/broken-env.json" | command grep -c .)"
[ "$o4" = 1 ] && pass "O4 the long --env spelling, inside a JSON string, is found" || fail_ "O4" "found $o4 (want 1)"
o5="$(_scan "$WORK/fine.md")"
[ -z "$o5" ] && pass "O5 name-first, continued name-first, Context7's form, prose mentions and add-json are NOT flagged" || fail_ "O5" "false positive(s): $(printf '%s' "$o5" | tr '\n' '|')"

# ── OM — mutation proofs: put ONE broken copy back into a real file ──────────
# The file is mirrored at its tracked path, the edit is asserted to have landed
# by its own text, and the scan over the mirror must report exactly one hit.
_mirror() {   # DIR — every tracked file that mentions the command, at its path
  local d="$1" f=""
  ( cd "$REPO_ROOT" && git ls-files ) | while IFS= read -r f; do
    [ -f "$REPO_ROOT/$f" ] || continue
    command grep -q 'claude mcp add' "$REPO_ROOT/$f" 2>/dev/null || continue
    mkdir -p "$d/$(dirname "$f")" && cp -p "$REPO_ROOT/$f" "$d/$f"
  done
  ( cd "$d" && git init -q . && git add -A . ) >/dev/null 2>&1
}
_om() {   # LABEL REL OLD NEW
  local label="$1" rel="$2" old="$3" new="$4" m="" n=""
  m="$(mktemp -d "$WORK/om.XXXXXX")"
  _mirror "$m"
  n="$(OLD="$old" NEW="$new" awk 'BEGIN{o=ENVIRON["OLD"]; w=ENVIRON["NEW"]; c=0}
        { i = index($0, o); if (i > 0 && c == 0) { $0 = substr($0, 1, i - 1) w substr($0, i + length(o)); c++ } print }
        END { print c > "/dev/stderr" }' "$m/$rel" 2>"$m/.n" > "$m/$rel.mut" && cat "$m/.n")"
  if [ "$n" != 1 ] || ! mv "$m/$rel.mut" "$m/$rel" || ! command grep -qF -- "$new" "$m/$rel"; then
    fail_ "$label" "the mutation did not apply (sites=$n)"; return
  fi
  _tracked_hits "$m" > "$m/.files"
  hits="$( while IFS= read -r f; do _scan "$f"; done < "$m/.files" )"
  if [ "$(printf '%s\n' "$hits" | command grep -c .)" = 1 ] && printf '%s' "$hits" | command grep -qF "$rel"; then
    pass "$label"
  else fail_ "$label" "the scan found '$(printf '%s' "$hits" | tr '\n' '|' | cut -c1-300)' (want exactly one hit, in $rel)"; fi
}
_om "OM1 register_qdrant_mcp put back to -e before the name — found" \
  scripts/lib/helpers-full.sh \
  'claude mcp add -s user qdrant -e QDRANT_URL=http://localhost:6333 -e COLLECTION_NAME=$collection --' \
  'claude mcp add -s user -e QDRANT_URL=http://localhost:6333 -e COLLECTION_NAME=$collection qdrant --'
_om "OM2 the Addendum's continued command put back to the name on its last line — found" \
  docs/cli-setup-addendum.md \
  'claude mcp add -s user qdrant \' \
  'claude mcp add -s user \'

# ── P — the Qdrant ports are published on LOOPBACK only (`# BL-311-MCP-LOOPBACK`) ──
# `-p 6333:6333` publishes the database on EVERY interface — no API key, and
# `--restart unless-stopped` keeps it there for as long as Docker runs. Every
# tracked `docker run` (and every copy printed for the operator to paste) must
# say `-p 127.0.0.1:6333:6333 -p 127.0.0.1:6334:6334`. The scan flags a
# `6333:6333` / `6334:6334` with no host address in front of it, and an
# explicit all-interfaces `0.0.0.0:`.
#
# ONE MORE ALLOWLISTED PATH, FOR A STATED REASON:
# docs/superpowers/plans/archive/ — frozen historical plans (the repo keeps its
#   archives as written; they are not instructions anyone runs).
PORT_ALLOW_PREFIXES="tests/test-bl311-mcp-add-order.sh docs/superpowers/plans/archive/"
_scan_ports() {   # FILE... — `file:line: text` for each unbound publication
  LC_ALL=C awk '{
      rest = $0; off = 0
      while (match(rest, /633[34]:633[34]/)) {
        pos = off + RSTART
        prev = (pos > 1) ? substr($0, pos - 1, 1) : ""
        bind = substr($0, 1, pos - 1)
        if (prev != ":" || bind ~ /0\.0\.0\.0:$/) { printf "%s:%d: %s\n", FILENAME, FNR, substr($0, 1, 160); break }
        off = pos + RLENGTH - 1; rest = substr($0, off + 1)
      }
    }' "$@"
}
_port_files() {   # ROOT — tracked files that publish the ports, minus the allowlist
  local root="$1" f="" a="" skipit=0
  ( cd "$root" && git ls-files ) | while IFS= read -r f; do
    [ -f "$root/$f" ] || continue
    skipit=0
    for a in $PORT_ALLOW_PREFIXES; do case "$f" in "$a"*) skipit=1 ;; esac; done
    [ "$skipit" -eq 1 ] && continue
    command grep -l '633[34]:633[34]' "$root/$f" 2>/dev/null
  done
}
_port_files "$REPO_ROOT" > "$WORK/pfiles"
p1_files=$(command grep -c . "$WORK/pfiles")
if [ "$p1_files" -gt 0 ]; then
  ( while IFS= read -r f; do _scan_ports "$f"; done < "$WORK/pfiles" ) > "$WORK/p1"
  if [ -s "$WORK/p1" ]; then
    sed "s#$REPO_ROOT/##; s#^#         (P1) #" "$WORK/p1" | cut -c1-160
    fail_ "P1 the tracked tree" "$(command grep -c . "$WORK/p1") Qdrant port publication(s) not bound to 127.0.0.1, listed above"
  else
    pass "P1 every tracked Qdrant port publication is bound to 127.0.0.1 ($p1_files file(s) publish them; the archive of old plans is allowlisted)"
  fi
else
  fail_ "P1 the tracked tree" "no tracked file publishes the Qdrant ports — the scan cannot be looking at the repository"
fi
cat > "$WORK/ports-bad.txt" <<'FIX'
docker run -d --name qdrant -p 6333:6333 -p 6334:6334 qdrant/qdrant:latest
  -p 6334:6334 \
docker run -p 0.0.0.0:6333:6333 qdrant/qdrant
FIX
cat > "$WORK/ports-fine.txt" <<'FIX'
docker run -d --name qdrant -p 127.0.0.1:6333:6333 -p 127.0.0.1:6334:6334 qdrant/qdrant:latest
  -p 127.0.0.1:6333:6333 -p 127.0.0.1:6334:6334 \
the database answers at http://localhost:6333
FIX
p2="$(_scan_ports "$WORK/ports-bad.txt" | command grep -c .)"
[ "$p2" = 3 ] && pass "P2 an unbound pair, an unbound continued line and an explicit 0.0.0.0 are each found" || fail_ "P2" "found $p2 (want 3)"
p3="$(_scan_ports "$WORK/ports-fine.txt")"
[ -z "$p3" ] && pass "P3 loopback-bound publications and a plain localhost URL are NOT flagged" || fail_ "P3" "false positive(s): $(printf '%s' "$p3" | tr '\n' '|')"
_pm() {   # LABEL REL OLD NEW — put ONE unbound publication back into a mirrored real file
  local label="$1" rel="$2" old="$3" new="$4" m="" n="" hits=""
  m="$(mktemp -d "$WORK/pm.XXXXXX")"
  ( cd "$REPO_ROOT" && git ls-files ) | while IFS= read -r f; do
    [ -f "$REPO_ROOT/$f" ] || continue
    command grep -q '633[34]:633[34]' "$REPO_ROOT/$f" 2>/dev/null || continue
    mkdir -p "$m/$(dirname "$f")" && cp -p "$REPO_ROOT/$f" "$m/$f"
  done
  ( cd "$m" && git init -q . && git add -A . ) >/dev/null 2>&1
  n="$(OLD="$old" NEW="$new" awk 'BEGIN{o=ENVIRON["OLD"]; w=ENVIRON["NEW"]; c=0}
        { i = index($0, o); if (i > 0 && c == 0) { $0 = substr($0, 1, i - 1) w substr($0, i + length(o)); c++ } print }
        END { print c > "/dev/stderr" }' "$m/$rel" 2>"$m/.n" > "$m/$rel.mut" && cat "$m/.n")"
  if [ "$n" != 1 ] || ! mv "$m/$rel.mut" "$m/$rel" || ! command grep -qF -- "$new" "$m/$rel"; then
    fail_ "$label" "the mutation did not apply (sites=$n)"; return
  fi
  _port_files "$m" > "$m/.files"
  hits="$( while IFS= read -r f; do _scan_ports "$f"; done < "$m/.files" )"
  if [ "$(printf '%s\n' "$hits" | command grep -c .)" = 1 ] && printf '%s' "$hits" | command grep -qF "$rel"; then
    pass "$label"
  else fail_ "$label" "the scan found '$(printf '%s' "$hits" | tr '\n' '|' | cut -c1-300)' (want exactly one hit, in $rel)"; fi
}
_pm "PM1 adoption's docker run put back to -p 6333:6333 (all interfaces) — found" \
  scripts/lib/adopt/adopt-mcp.sh \
  '-p 127.0.0.1:6333:6333 -p 127.0.0.1:6334:6334 -v' \
  '-p 6333:6333 -p 6334:6334 -v'
_pm "PM2 init.sh's continued docker run put back to all interfaces — found" \
  init.sh \
  '            -p 127.0.0.1:6333:6333 -p 127.0.0.1:6334:6334 \' \
  '            -p 6333:6333 -p 6334:6334 \'

echo
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

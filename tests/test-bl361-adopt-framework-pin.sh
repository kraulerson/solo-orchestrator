#!/usr/bin/env bash
# tests/test-bl361-adopt-framework-pin.sh — `## BL-361:` adoption pins
# `soloFrameworkCommit`, and `## BL-363:` makes a files{} sha the same whatever
# path it was hashed by, which the pin makes reachable.
#
# THE DEFECTS. init.sh pins the framework commit a project was built from
# (`# BL-110-PIN-UNIVERSAL`); adoption pinned nothing, so the freshness check's
# framework-drift and orphan arms skipped every adopted project. With the pin,
# a project under a path holding a backslash showed the second defect: shasum
# and GNU sha256sum answer such a NAME with `\<hex>`, adoption hashed absolute
# paths, and the framework side (a path without one) gave plain hex — 86 false
# framework-drift items with nothing changed. init.sh's "." stamp had the
# mirror image: plain rows against a reader hashing the absolute path, one false
# local edit per row.
#
# CASES
#   N1  an adoption pins soloFrameworkCommit to the framework clone's HEAD,
#       init.sh's derivation (`git -C <framework> rev-parse HEAD`, no suffix),
#       in the adoption commit; init.sh's derivation line is still that one
#   N2  the pinned adoptee, under a path holding a backslash and a space: every
#       files{} sha is plain hex, and the freshness detector finds no local
#       edit, framework drift, orphan or missing file
#   N3  real drift on that adoptee is still reported: a file installed from an
#       older framework is `fw-drift`, not a local edit, a pin older than HEAD
#       is `pin-behind`, and without the pin neither arm runs
#   N4  never a re-stamp: re-running adoption refuses with the manifest
#       byte-identical; the writer refuses a manifest that has the pin but no
#       currency block, and stamps both when it has neither
#   N5  a framework dir that is not a git checkout: the writer stamps the
#       currency block, writes no pin and says so (init.sh's skip)
#   B1  soif_currency_sha256 gives plain hex for a file hashed by a path
#       holding a backslash, through shasum and through sha256sum
#   B2  the batch (`# BL-337-BATCH-HASH`) gives plain hex rows for a project
#       hashed by such a path, through both tools
#   B3  an init.sh-shaped stamp (project dir ".", from inside it) under such a
#       path, pinned at HEAD: no local edit and no framework drift; an edited
#       file is the one local edit
#   B4  the readers' own fallbacks (_soif_fresh_sha, _soif_plan_sha, used when
#       the currency lib is not loaded) give plain hex for such a path
#   C1  an adoptee stamped before the fix (every files{} sha `\`-prefixed),
#       pinned at HEAD: no local edit and no framework drift; a real edit is
#       still the one local edit
#   C2  a render base stamped `\`-prefixed is not an older template; a stale
#       one still is
#   C3  --plan's rename linkage pairs a retire whose stored sha is
#       `\`-prefixed with the add it matches
#
# Hermetic: temp dirs only, no network (SOIF_FRESHNESS_FETCH=0, no Guardrails
# clone, no MCP step). Reads init.sh as source and never runs it. Needs the
# framework clone's history one commit deep (N3; the unit lane checks out with
# fetch-depth 0). bash 3.2 safe.
set -uo pipefail
unset GITHUB_BASE_REF 2>/dev/null || true
export SOIF_ADOPT_MCP=off   # BL-311-MCP-SEAM
export SOIF_FRESHNESS_FETCH=0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

echo "== BL-361 / BL-363 — adoption pins the framework commit; shas are path-independent =="
for t in jq git shasum; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/bl361.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT INT TERM
gitq() { git -C "$1" "${@:2}" >/dev/null 2>&1; }
FW_HEAD="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)"
[ -n "$FW_HEAD" ] || { echo "fixture: the framework clone has no HEAD"; exit 1; }
BS="$WORK/ad\\opt q"   # a backslash AND a space, the path shasum escapes
mkdir -p "$BS" || exit 1

# ── fixtures ─────────────────────────────────────────────────────────────────
# The adoptee and answers of tests/test-bl337-adopt-currency-stamp.sh.
mk_adoptee() {
  local p="$1"
  mkdir -p "$p/src" || return 1
  gitq "$p" init -q . && gitq "$p" config user.email bl361@test.invalid && gitq "$p" config user.name "BL361 Test" \
    && gitq "$p" config core.excludesFile /dev/null || return 1
  printf '{"name":"acme-api","scripts":{"test":"npm test"}}\n' > "$p/package.json"
  printf '# acme-api\n' > "$p/README.md"
  printf 'node_modules/\n' > "$p/.gitignore"
  gitq "$p" add package.json README.md .gitignore && gitq "$p" commit -q --no-verify -m "chore: their own history"
}
run_adopt() {   # DIR OUTFILE — sets RUN_RC
  RUN_RC=0
  ( cd "$1" && printf '1\nstandard\n1\n1\n1\n1\n' | env SOIF_ADOPT_SCANNER_BIN=sh SOIF_ADOPT_QDRANT=no \
      SOIF_ADOPT_GUARDRAILS_DIR="$WORK/no-guardrails" bash "$REPO_ROOT/scripts/adopt-project.sh" ) \
    > "$2" 2>&1 || RUN_RC=$?
}
# detect LIBDIR PROJ — the freshness detector's items (TSV: id check tier path
# verb sig msg) from LIBDIR's copy of it, against the framework the manifest names.
detect() {
  bash -c '. "$1/freshness-detect.sh" || exit 9
    m="$2/.claude/manifest.json"; fw="$(jq -r ".currency.soloFrameworkPath // empty" "$m")"
    soif_freshness_detect "$2" "$m" "$fw" "$fw/init.sh" "$3"' _ "$1" "$2" "$WORK/no-cdf" 2>/dev/null
}
count() { printf '%s\n' "$1" | awk -F'\t' -v c="$2" '$2 == c' | awk 'END { print NR }'; }
plain_sha() { shasum -a 256 "$1" | awk '{ h = $1; sub(/^\\/, "", h); print h }'; }
# The adoption writer, called directly with the driver's libs sourced (the
# driver would refuse at its preflight first). FW is the framework it pins from.
writer() {   # DIR FW — prints the writer's output, returns its rc
  ( cd "$REPO_ROOT" || exit 9
    for l in helpers-core render-project-docs tldr-mode claude-settings adoption-stamp scaffold-shipped-set hook-templates \
             enforcement-level tdd-classify bypass-audit guardrails currency-manifest; do
      . "scripts/lib/$l.sh" || exit 9
    done
    for l in adopt-core adopt-evidence adopt-intake adopt-tools adopt-mcp adopt-secrets adopt-state adopt-record adopt-docs \
             adopt-ci adopt-session adopt-guardrails adopt-act4 adopt-archive adopt-stubs adopt-test-debt; do
      . "scripts/lib/adopt/$l.sh" || exit 9
    done
    command -v adopt_write_currency >/dev/null 2>&1 || { echo "NO-WRITER"; exit 8; }
    ADOPT_FRAMEWORK_ROOT="$2"; ADOPT_WRITTEN_LEDGER="$1.ledger"; ADOPT_GUARD_REAL_ROOT=""
    cp "$1/.claude/adoption/write-set.txt" "$ADOPT_WRITTEN_LEDGER" || { echo "NO-WRITE-SET"; exit 8; }
    adopt_write_currency "$1" "$1/.claude/adoption/scout-report.json" ) 2>&1
}
set_json() {   # FILE JQ-FILTER [jq args...] — rewrite FILE through jq
  local f="$1" flt="$2"; shift 2
  jq "$@" "$flt" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

P="$BS/p"
mk_adoptee "$P" || { echo "fixture failed"; exit 1; }
run_adopt "$P" "$WORK/adopt.out"
ADOPT_RC=$RUN_RC
M="$P/.claude/manifest.json"
if [ "$ADOPT_RC" -ne 0 ]; then
  echo "fixture: adoption under '$BS' failed, rc $ADOPT_RC: $(command grep -E 'BLOCKED|REFUSED' "$WORK/adopt.out" | head -2 | tr '\n' ' ')"
  echo "Results: $PASSED passed, 1 failed, $SKIPPED skipped"; exit 1
fi

echo
echo "=== N — adoption pins the framework commit (BL-361) ==="
n1() {
  local label="N1 an adoption pins soloFrameworkCommit to the framework clone's HEAD, as init.sh derives it, in the adoption commit" bad="" got
  got="$(jq -r '.soloFrameworkCommit // "(absent)"' "$M" 2>/dev/null)"
  [ "$got" = "$FW_HEAD" ] || bad="$bad [soloFrameworkCommit=$got, framework HEAD=$FW_HEAD]"
  [ "$(git -C "$P" show HEAD:.claude/manifest.json 2>/dev/null | jq -r '.soloFrameworkCommit // ""')" = "$FW_HEAD" ] \
    || bad="$bad [the adoption commit does not carry the pin]"
  command grep -qF '_solo_fw_commit="$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || echo "")"' "$REPO_ROOT/init.sh" \
    || bad="$bad [init.sh's derivation changed; re-mirror adopt_write_currency's pin (# BL-361-ADOPT-PIN)]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
n2() {
  local label="N2 the pinned adoptee under a path holding a backslash: plain-hex rows; no local edit, framework drift, orphan or missing item" bad="" out n c
  n="$(jq '[.currency.files[] | select((.sha256 | test("^[0-9a-f]{64}$")) | not)] | length' "$M" 2>/dev/null)"
  [ "$n" = "0" ] || bad="$bad [$n files{} sha(s) are not plain hex: $(jq -r '.currency.files["scripts/check-phase-gate.sh"].sha256' "$M")]"
  out="$(detect "$P/scripts/lib" "$P")"
  for c in local-edit framework-drift orphan missing; do
    n="$(count "$out" "$c")"; [ "$n" = "0" ] || bad="$bad [$n $c item(s), e.g. $(printf '%s\n' "$out" | awk -F'\t' -v c="$c" '$2 == c { print $1; exit }')]"
  done
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
n3() {
  local label="N3 real drift on the pinned adoptee is reported: an older install is fw-drift (not a local edit), an older pin is pin-behind; unpinned, neither" \
    c="$WORK/n3" bad="" out rel="docs/reference/builders-guide.md" sha prev
  prev="$(git -C "$REPO_ROOT" rev-parse HEAD~1 2>/dev/null)" || { fail_ "$label" "fixture: the framework clone has no HEAD~1 (a shallow checkout; fetch-depth 0 is needed)"; return; }
  cp -R "$P" "$c" || { fail_ "$label" "copy failed"; return; }
  # "Installed from an older framework": the project holds other bytes, recorded as installed.
  printf '\nA line the framework has since removed.\n' >> "$c/$rel"
  sha="$(plain_sha "$c/$rel")"
  set_json "$c/.claude/manifest.json" '.currency.files[$r].sha256 = $s | .soloFrameworkCommit = $p' --arg r "$rel" --arg s "$sha" --arg p "$prev"
  out="$(detect "$c/scripts/lib" "$c")"
  printf '%s\n' "$out" | awk -F'\t' -v i="fw-drift:$rel" '$1 == i' | command grep -q . || bad="$bad [no fw-drift:$rel]"
  printf '%s\n' "$out" | awk -F'\t' -v i="local-edit:$rel" '$1 == i' | command grep -q . && bad="$bad [the older install is called a local edit]"
  [ "$(count "$out" framework-drift)" = "1" ] || bad="$bad [$(count "$out" framework-drift) framework-drift items, want 1]"
  printf '%s\n' "$out" | awk -F'\t' '$1 == "pin-behind"' | command grep -q 'ahead of your pin' || bad="$bad [no pin-behind item for a pin at HEAD~1]"
  set_json "$c/.claude/manifest.json" 'del(.soloFrameworkCommit)'
  out="$(detect "$c/scripts/lib" "$c")"
  [ "$(count "$out" framework-drift)" = "0" ] || bad="$bad [unpinned, the drift arm still ran: the case does not show the pin is what enables it]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
n4() {
  local label="N4 never a re-stamp: a re-run refuses, manifest byte-identical; the writer refuses a pin without a currency block, stamps both with neither" \
    c="$WORK/n4" bad="" out rc before
  cp "$M" "$WORK/m.before"
  run_adopt "$P" "$WORK/adopt2.out"
  [ "$RUN_RC" -ne 0 ] || bad="$bad [the re-run did not refuse]"
  cmp -s "$WORK/m.before" "$M" || bad="$bad [the re-run changed the manifest: $(cmp "$WORK/m.before" "$M" 2>&1)]"
  cp -R "$P" "$c" || { fail_ "$label" "copy failed"; return; }
  set_json "$c/.claude/manifest.json" 'del(.currency) | .soloFrameworkCommit = "0000000000000000000000000000000000000000"'
  before="$(cat "$c/.claude/manifest.json")"
  rc=0; out="$(writer "$c" "$REPO_ROOT")" || rc=$?
  if [ "$rc" -eq 0 ] || [ "$before" != "$(cat "$c/.claude/manifest.json")" ] || ! printf '%s' "$out" | command grep -q 'backfill'; then
    bad="$bad [pin present, no currency: rc $rc, changed=$([ "$before" = "$(cat "$c/.claude/manifest.json")" ] && echo no || echo yes), out: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')]"
  fi
  set_json "$c/.claude/manifest.json" 'del(.currency) | del(.soloFrameworkCommit)'
  rc=0; out="$(writer "$c" "$REPO_ROOT")" || rc=$?
  [ "$rc" -eq 0 ] && [ "$(jq -r '.soloFrameworkCommit // ""' "$c/.claude/manifest.json")" = "$FW_HEAD" ] \
    && jq -e '.currency.schemaVersion == 1' "$c/.claude/manifest.json" >/dev/null 2>&1 \
    || bad="$bad [positive control, neither present: rc $rc, pin=$(jq -r '.soloFrameworkCommit // "(absent)"' "$c/.claude/manifest.json"), out: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
n5() {
  local label="N5 a framework dir that is not a git checkout: the currency block is stamped, no pin is written, and the writer says so" \
    c="$WORK/n5" fw="$WORK/n5-fw" bad="" out rc=0 x
  mkdir -p "$fw" || { fail_ "$label" "mkdir"; return; }
  for x in init.sh scripts templates docs; do ln -s "$REPO_ROOT/$x" "$fw/$x" || { fail_ "$label" "symlink $x"; return; }; done
  if GIT_CEILING_DIRECTORIES="$WORK" git -C "$fw" rev-parse --git-dir >/dev/null 2>&1; then fail_ "$label" "fixture: $fw is inside a git checkout"; return; fi
  cp -R "$P" "$c" || { fail_ "$label" "copy failed"; return; }
  set_json "$c/.claude/manifest.json" 'del(.currency) | del(.soloFrameworkCommit)'
  out="$(GIT_CEILING_DIRECTORIES="$WORK" writer "$c" "$fw")" || rc=$?
  [ "$rc" -eq 0 ] || bad="$bad [rc $rc: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')]"
  jq -e '.currency.schemaVersion == 1' "$c/.claude/manifest.json" >/dev/null 2>&1 || bad="$bad [no currency block]"
  jq -e 'has("soloFrameworkCommit") | not' "$c/.claude/manifest.json" >/dev/null 2>&1 || bad="$bad [a pin was written: $(jq -r '.soloFrameworkCommit' "$c/.claude/manifest.json")]"
  printf '%s' "$out" | command grep -q 'not a git checkout' || bad="$bad [the writer did not say why there is no pin]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
n1; n2; n3; n4; n5

echo
echo "=== B — a sha is the same whatever path hashed it (BL-363) ==="
# A PATH of symlinks to every command on this PATH except shasum and sha256sum
# (tests/test-bl337-adopt-currency-stamp.sh H1's recipe), plus a sha256sum that
# escapes a backslash in a name as GNU's does — shasum's own format — so the
# sha256sum arm is the one under test on every host, macOS's non-escaping
# sha256sum included.
SUMBIN="$WORK/sum-bin"
mk_sumbin() {
  local real="" d="" f="" n=""
  mkdir -p "$SUMBIN" || return 1
  real="$(command -v shasum)" || return 1
  printf '#!/bin/sh\nexec "%s" -a 256 "$@"\n' "$real" > "$SUMBIN/sha256sum" && chmod +x "$SUMBIN/sha256sum" || return 1
  printf '%s\n' "$PATH" | tr ':' '\n' > "$WORK/sum-path"
  while IFS= read -r d; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      n="${f##*/}"
      case "$n" in shasum*|sha256sum) continue ;; esac
      [ -f "$f" ] && [ -x "$f" ] && [ ! -e "$SUMBIN/$n" ] && ln -s "$f" "$SUMBIN/$n"
    done
  done < "$WORK/sum-path"
  PATH="$SUMBIN" command -v shasum >/dev/null 2>&1 && return 1
  [ "$(PATH="$SUMBIN" sha256sum "$P/README.md" 2>/dev/null | cut -c1)" = '\' ]
}
mk_sumbin || { echo "fixture: could not build the sha256sum-only PATH"; exit 1; }
B="$BS/b"
mkdir -p "$B" && printf 'some bytes\n' > "$B/f" || exit 1
WANT="$(cd "$B" && shasum -a 256 f | awk '{print $1}')"
b1() {
  local label="B1 soif_currency_sha256 gives plain hex for a file hashed by a path holding a backslash, through shasum and through sha256sum" bad="" got
  got="$(bash -c '. "$1/scripts/lib/currency-manifest.sh"; soif_currency_sha256 "$2"' _ "$REPO_ROOT" "$B/f" 2>/dev/null)"
  [ "$got" = "$WANT" ] || bad="$bad [shasum: '$got', want '$WANT']"
  got="$(bash -c '. "$1/scripts/lib/currency-manifest.sh"; PATH="$3"; soif_currency_sha256 "$2"' _ "$REPO_ROOT" "$B/f" "$SUMBIN" 2>/dev/null)"
  [ "$got" = "$WANT" ] || bad="$bad [sha256sum: '$got', want '$WANT']"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
# A tiny init.sh-shaped project: two shipped scripts and a shipped guide.
IP="$BS/proj two"
mkdir -p "$IP/scripts" "$IP/docs/reference" "$IP/.claude" || exit 1
cp "$REPO_ROOT/scripts/check-phase-gate.sh" "$REPO_ROOT/scripts/session-freshness-check.sh" "$IP/scripts/" \
  && cp "$REPO_ROOT/docs/builders-guide.md" "$IP/docs/reference/builders-guide.md" \
  && printf '# rendered\n' > "$IP/CLAUDE.md" || exit 1
b2() {
  local label="B2 the batch gives plain-hex files{} rows for a project hashed by a path holding a backslash, through both tools" bad="" blk="" rel="" want="" got="" mode=""
  for mode in shasum sha256sum; do
    if [ "$mode" = shasum ]; then
      blk="$(bash -c '. "$1/scripts/lib/currency-manifest.sh"; soif_currency_block "$1/init.sh" "$1" "$2" node "$1"' _ "$REPO_ROOT" "$IP" 2>"$WORK/b2.err")"
    else
      blk="$(bash -c '. "$1/scripts/lib/currency-manifest.sh"; PATH="$3"; soif_currency_block "$1/init.sh" "$1" "$2" node "$1"' _ "$REPO_ROOT" "$IP" "$SUMBIN" 2>"$WORK/b2.err")"
    fi
    for rel in scripts/check-phase-gate.sh docs/reference/builders-guide.md; do
      want="$(cd "$IP" && shasum -a 256 "$rel" | awk '{print $1}')"
      got="$(printf '%s' "$blk" | jq -r --arg r "$rel" '.files[$r].sha256 // ""' 2>/dev/null)"
      [ "$got" = "$want" ] || bad="$bad [$mode: $rel row is '$got', want $want; stderr: $(head -1 "$WORK/b2.err")]"
    done
  done
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
# init.sh's stamp, as init.sh calls it: from inside the project, project dir "."
# (`# BL-109-CURRENCY`), the render base captured at the render site; then the
# pin init.sh writes.
( cd "$IP" && bash -c '. "$1/scripts/lib/currency-manifest.sh"
    printf "{\"host\":\"github\"}\n" > .claude/manifest.json
    soif_currency_renderbase_init
    soif_currency_record_render_base A1 CLAUDE.md "$1/templates/generated/claude-md.tmpl" CLAUDE.md
    soif_currency_stamp .claude/manifest.json "$1/init.sh" "$1" "." node "$1"
    rm -f "$SOIF_CURRENCY_RENDERBASE_FILE"' _ "$REPO_ROOT" ) >/dev/null 2>&1
set_json "$IP/.claude/manifest.json" '.soloFrameworkCommit = $c' --arg c "$FW_HEAD"
b3() {
  local label="B3 an init.sh-shaped stamp under a path holding a backslash, pinned at HEAD: no local edit, no framework drift; an edit is the one local edit" \
    c="$BS/b3" bad="" out n
  n="$(jq '.currency.files | length' "$IP/.claude/manifest.json" 2>&1)"
  case "$n" in
    [3-9]|[1-9][0-9]*) : ;;
    *) fail_ "$label" "fixture: the stamp did not land (files: $n): $(head -c 300 "$IP/.claude/manifest.json")"; return ;;
  esac
  out="$(detect "$REPO_ROOT/scripts/lib" "$IP")"
  n="$(count "$out" local-edit)"; [ "$n" = "0" ] || bad="$bad [$n local-edit item(s)]"
  n="$(count "$out" framework-drift)"; [ "$n" = "0" ] || bad="$bad [$n framework-drift item(s)]"
  cp -R "$IP" "$c" || { fail_ "$label" "copy failed"; return; }
  printf '# an edit\n' >> "$c/scripts/session-freshness-check.sh"
  out="$(detect "$REPO_ROOT/scripts/lib" "$c")"
  [ "$(printf '%s\n' "$out" | awk -F'\t' '$2 == "local-edit" { print $1 }')" = "local-edit:scripts/session-freshness-check.sh" ] \
    || bad="$bad [control: local-edit items are '$(printf '%s\n' "$out" | awk -F'\t' '$2 == "local-edit" { print $1 }' | tr '\n' ' ')']"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
b4() {
  local label="B4 the readers' fallbacks (_soif_fresh_sha, _soif_plan_sha) give plain hex for a path holding a backslash" bad="" got fn
  for fn in _soif_fresh_sha _soif_plan_sha; do
    got="$(bash -c '. "$1/scripts/lib/plan-staging.sh"; unset -f soif_currency_sha256; "$3" "$2"' _ "$REPO_ROOT" "$B/f" "$fn" 2>/dev/null)"
    [ "$got" = "$WANT" ] || bad="$bad [$fn: '$got']"
  done
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
b1; b2; b3; b4

echo
echo "=== C — rows stamped before the fix still read as current ==="
c1() {
  local label="C1 an adoptee whose files{} shas are \\-prefixed (stamped before the fix), pinned at HEAD: no local edit, no drift; a real edit still is one" \
    c="$BS/c1" bad="" out n
  cp -R "$P" "$c" || { fail_ "$label" "copy failed"; return; }
  set_json "$c/.claude/manifest.json" '.currency.files |= map_values(.sha256 = "\\" + (.sha256 | ltrimstr("\\")))'
  [ "$(jq -r '.currency.files["scripts/check-phase-gate.sh"].sha256 | .[0:1]' "$c/.claude/manifest.json")" = '\' ] || { fail_ "$label" "fixture: rows not prefixed"; return; }
  out="$(detect "$c/scripts/lib" "$c")"
  n="$(count "$out" local-edit)"; [ "$n" = "0" ] || bad="$bad [$n local-edit item(s)]"
  n="$(count "$out" framework-drift)"; [ "$n" = "0" ] || bad="$bad [$n framework-drift item(s)]"
  printf '# an edit\n' >> "$c/scripts/session-freshness-check.sh"
  out="$(detect "$c/scripts/lib" "$c")"
  [ "$(printf '%s\n' "$out" | awk -F'\t' '$2 == "local-edit" { print $1 }')" = "local-edit:scripts/session-freshness-check.sh" ] \
    || bad="$bad [control: local-edit items are '$(printf '%s\n' "$out" | awk -F'\t' '$2 == "local-edit" { print $1 }' | tr '\n' ' ')']"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
c2() {
  local label="C2 a \\-prefixed render base is not an older template; a stale one still is" c="$BS/c2" bad="" out tsha
  cp -R "$IP" "$c" || { fail_ "$label" "copy failed"; return; }
  tsha="$(plain_sha "$REPO_ROOT/templates/generated/claude-md.tmpl")"
  set_json "$c/.claude/manifest.json" '.currency.renderBases.A1["CLAUDE.md"].templateSha = ("\\" + $t)' --arg t "$tsha"
  out="$(detect "$REPO_ROOT/scripts/lib" "$c")"
  [ "$(count "$out" render-base)" = "0" ] || bad="$bad [a \\-prefixed base reads as an older template]"
  set_json "$c/.claude/manifest.json" '.currency.renderBases.A1["CLAUDE.md"].templateSha = "0000000000000000000000000000000000000000000000000000000000000000"'
  out="$(detect "$REPO_ROOT/scripts/lib" "$c")"
  [ "$(count "$out" render-base)" = "1" ] || bad="$bad [control: a stale base gives $(count "$out" render-base) render-base item(s)]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
c3() {
  local label="C3 --plan's rename linkage pairs a retire whose stored sha is \\-prefixed with the add it matches" bad="" mani="$WORK/c3.json" items="$WORK/c3.items" tsha pre got
  tsha="$(plain_sha "$REPO_ROOT/scripts/check-phase-gate.sh")"
  for pre in "" '\'; do
    jq -n --arg s "$pre$tsha" '{currency: {files: {"scripts/old-gate.sh": {sha256: $s, mode: "755", class: "M", state: "current"}}}}' > "$mani"
    printf 'orphan:scripts/old-gate.sh\tM\tretire\tenforcement\tscripts/old-gate.sh\titem\t\nadd:scripts/check-phase-gate.sh\tM\tadd\tenforcement\tscripts/check-phase-gate.sh\tbatch\t\n' > "$items"
    bash -c 'for l in hook-templates scaffold-shipped-set currency-manifest freshness-detect render-project-docs plan-staging; do . "$1/scripts/lib/$l.sh"; done
      _soif_plan_link_renames "$2" "$1" "$1/init.sh" "$3"' _ "$REPO_ROOT" "$mani" "$items" >/dev/null 2>&1
    got="$(awk -F'\t' '$3 == "rename" { print $1 }' "$items" | tr '\n' ' ')"
    [ "$got" = "orphan:scripts/old-gate.sh add:scripts/check-phase-gate.sh " ] || bad="$bad [stored '${pre}<sha>': renames '$got']"
  done
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
c1; c2; c3

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]

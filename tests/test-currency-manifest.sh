#!/usr/bin/env bash
# tests/test-currency-manifest.sh — BL-109 S1 unit lane (LIB-LEVEL ONLY).
#
# Exercises scripts/lib/currency-manifest.sh + the scaffold-shipped-set.sh
# extensions WITHOUT ever invoking init.sh (fast-lane invariant: this test is in
# the tests.yml unit list, so it must not scaffold a project). It builds a tiny
# hermetic framework+project fixture, populates a render-base scratch file the
# way init.sh's render sites would, stamps a `currency` block into a fixture
# manifest, and asserts the schema, class assignment, hook enum, sha/mode
# capture, render-base capture, reader/writer round-trip, additive merge, the
# state:"current" field, and the dual-source ban.
#
# The AGGREGATOR fidelity test (tests/test-currency-birth-stamp.sh) runs the REAL
# init.sh and proves the shas recompute end-to-end — the BL-088 precedent that
# fixtures hide scaffold gaps. This unit test proves the LIB's behavior.
#
# bash-3.2 safe. Hermetic (mktemp, no network, no remotes).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

unset GITHUB_BASE_REF 2>/dev/null || true

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# assert_eq <label> <expected> <actual>
assert_eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq required for the currency-manifest unit test"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

# ── Load the lib under test (+ its deps) ────────────────────────────────────
# shellcheck source=/dev/null
. "$REPO_ROOT/scripts/lib/hook-templates.sh"
# shellcheck source=/dev/null
. "$REPO_ROOT/scripts/lib/scaffold-shipped-set.sh"
# shellcheck source=/dev/null
. "$REPO_ROOT/scripts/lib/currency-manifest.sh"

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# ════════════════════════════════════════════════════════════════════════════
# T1 — sha/mode capture correctness
# ════════════════════════════════════════════════════════════════════════════
echo "== T1: sha256 + mode capture =="
KNOWN="$TOPTMP/known.txt"
printf 'currency-fixture-content\n' > "$KNOWN"
chmod 640 "$KNOWN"
want_sha="$(shasum -a 256 "$KNOWN" | awk '{print $1}')"
got_sha="$(soif_currency_sha256 "$KNOWN")"
assert_eq "T1-sha256 matches independent shasum" "$want_sha" "$got_sha"
want_mode="$(stat -c '%a' "$KNOWN" 2>/dev/null || stat -f '%Lp' "$KNOWN" 2>/dev/null)"
got_mode="$(soif_currency_mode "$KNOWN")"
assert_eq "T1-mode matches independent stat" "$want_mode" "$got_mode"
assert_eq "T1-mode is the chmod'd 640" "640" "$got_mode"
if soif_currency_sha256 "$TOPTMP/does-not-exist" >/dev/null 2>&1; then
  fail "T1-sha256 missing-file returns non-zero" "returned success"
else
  pass "T1-sha256 missing-file returns non-zero"
fi

# ════════════════════════════════════════════════════════════════════════════
# T2 — hook three-state enum derivation (language matrix)
# ════════════════════════════════════════════════════════════════════════════
echo "== T2: hook enum (language matrix) =="
assert_eq "T2-commit-msg typescript -> present"        "present"            "$(soif_currency_hook_state commit-msg typescript)"
assert_eq "T2-commit-msg python -> present"            "present"            "$(soif_currency_hook_state commit-msg python)"
assert_eq "T2-commit-msg go -> present"                "present"            "$(soif_currency_hook_state commit-msg go)"
# BL-107-UNIVERSAL-INSTALL: these four used to pin the SKIP (rust ->
# absent-intentional, other/cobol/empty -> absent-unavailable) — that pinned
# the bug: two whole language axes shipped with no TDD/BL-006 commit-msg gate.
# The gate now installs for every language; the enum values remain reader-side
# legacy states (pre-BL-107 manifests), covered by test-freshness-check.sh.
assert_eq "T2-commit-msg rust -> present (BL-107)"     "present"            "$(soif_currency_hook_state commit-msg rust)"
assert_eq "T2-commit-msg other -> present (BL-107)"    "present"            "$(soif_currency_hook_state commit-msg other)"
assert_eq "T2-commit-msg cobol -> present (BL-107)"    "present"            "$(soif_currency_hook_state commit-msg cobol)"
assert_eq "T2-commit-msg empty -> present (BL-107)"    "present"            "$(soif_currency_hook_state commit-msg '')"
assert_eq "T2-pre-commit typescript -> present"        "present"            "$(soif_currency_hook_state pre-commit typescript)"
assert_eq "T2-pre-commit rust -> present"              "present"            "$(soif_currency_hook_state pre-commit rust)"
assert_eq "T2-unknown-hook -> absent-unavailable"      "absent-unavailable" "$(soif_currency_hook_state pre-push rust)"

# ════════════════════════════════════════════════════════════════════════════
# Build a hermetic framework+project fixture for the stamp-based tests (T3–T8).
# The fixture mirrors init.sh's shape: cp lines for scripts + a reference doc,
# a `for skill in ... ; do` loop (multi-line, matching init.sh), and A1/A2
# render sources. The scaffolded project holds byte-copies + rendered artifacts.
# ════════════════════════════════════════════════════════════════════════════
echo "== building fixture =="
FW="$TOPTMP/fw"
PROJ="$TOPTMP/proj"
mkdir -p "$FW/scripts/lib" "$FW/scripts/host-drivers" "$FW/docs" \
         "$FW/templates/generated/skills/alpha-skill" \
         "$FW/templates/generated/skills/beta-skill" \
         "$FW/templates/generated"
mkdir -p "$PROJ/scripts/lib" "$PROJ/scripts/host-drivers" "$PROJ/docs/reference" \
         "$PROJ/.claude/skills/alpha-skill" "$PROJ/.claude/skills/beta-skill" "$PROJ/.claude"

# Framework sources
printf 'echo alpha\n'         > "$FW/scripts/alpha.sh"
printf 'lib=beta\n'           > "$FW/scripts/lib/hook-templates.sh"
printf 'driver\n'             > "$FW/scripts/host-drivers/github.driver.sh"
printf '# builders guide\n'   > "$FW/docs/builders-guide.md"
printf 'ALPHA SKILL\n'        > "$FW/templates/generated/skills/alpha-skill/SKILL.md"
printf 'ALPHA NOTICE\n'       > "$FW/templates/generated/skills/alpha-skill/NOTICE"
printf 'BETA SKILL\n'         > "$FW/templates/generated/skills/beta-skill/SKILL.md"   # beta has NO NOTICE
printf 'CLAUDE TEMPLATE __PROJECT_NAME__\n' > "$FW/templates/generated/claude-md.tmpl"
printf 'INTAKE TEMPLATE __DATE__\n'         > "$FW/templates/project-intake.md"
printf 'BIBLE SKELETON [N]\n'               > "$FW/templates/generated/project-bible.tmpl"
printf 'MANIFESTO SKELETON\n'               > "$FW/templates/generated/product-manifesto.tmpl"

# Fixture init.sh — MECHANICAL source for the parsers (never executed here).
cat > "$FW/init.sh" <<'FIXTURE_INIT'
  cp "$SCRIPT_DIR/scripts/alpha.sh" scripts/
  cp "$SCRIPT_DIR/scripts/lib/hook-templates.sh" scripts/lib/
  cp "$SCRIPT_DIR/scripts/host-drivers/"*.sh scripts/host-drivers/
  cp "$SCRIPT_DIR/docs/builders-guide.md" docs/reference/
  for skill in alpha-skill beta-skill; do
    cp "$SCRIPT_DIR/templates/generated/skills/$skill/SKILL.md" ".claude/skills/$skill/"
  done
FIXTURE_INIT

# Scaffolded project = byte copies + rendered artifacts.
cp "$FW/scripts/alpha.sh"                                   "$PROJ/scripts/alpha.sh"
cp "$FW/scripts/lib/hook-templates.sh"                      "$PROJ/scripts/lib/hook-templates.sh"
cp "$FW/scripts/host-drivers/github.driver.sh"             "$PROJ/scripts/host-drivers/github.driver.sh"
cp "$FW/docs/builders-guide.md"                            "$PROJ/docs/reference/builders-guide.md"
cp "$FW/templates/generated/skills/alpha-skill/SKILL.md"   "$PROJ/.claude/skills/alpha-skill/SKILL.md"
cp "$FW/templates/generated/skills/alpha-skill/NOTICE"     "$PROJ/.claude/skills/alpha-skill/NOTICE"
cp "$FW/templates/generated/skills/beta-skill/SKILL.md"    "$PROJ/.claude/skills/beta-skill/SKILL.md"
printf 'CLAUDE RENDERED fixtureproj\n' > "$PROJ/CLAUDE.md"
printf 'INTAKE RENDERED 2026-07-12\n'  > "$PROJ/PROJECT_INTAKE.md"

# Pre-existing manifest with pins that MUST survive the additive stamp.
printf '{"host":"github","mode":"personal","soloFrameworkCommit":"deadbeef","frameworkCommit":"cafef00d"}\n' \
  > "$PROJ/.claude/manifest.json"

# Populate the render-base scratch the way init.sh's render sites do.
soif_currency_renderbase_init
soif_currency_record_render_base A1 CLAUDE.md \
  "$FW/templates/generated/claude-md.tmpl" "$PROJ/CLAUDE.md"
soif_currency_record_render_base A1 PROJECT_INTAKE.md \
  "$FW/templates/project-intake.md" "$PROJ/PROJECT_INTAKE.md"
soif_currency_record_render_base A2 PROJECT_BIBLE.md \
  "$FW/templates/generated/project-bible.tmpl" ""
soif_currency_record_render_base A2 PRODUCT_MANIFESTO.md \
  "$FW/templates/generated/product-manifesto.tmpl" ""

MAN="$PROJ/.claude/manifest.json"
soif_currency_stamp "$MAN" "$FW/init.sh" "$FW" "$PROJ" typescript "$FW"

# ════════════════════════════════════════════════════════════════════════════
# T3 — schema shape (design v1.1 §2-L0)
# ════════════════════════════════════════════════════════════════════════════
echo "== T3: schema shape =="
assert_eq "T3-schemaVersion == 1"     "1"     "$(jq -r '.currency.schemaVersion' "$MAN")"
assert_eq "T3-soloFrameworkPath set"  "$FW"   "$(jq -r '.currency.soloFrameworkPath' "$MAN")"
assert_eq "T3-files is an object"     "object" "$(jq -r '.currency.files | type' "$MAN")"
assert_eq "T3-renderBases.A1 object"  "object" "$(jq -r '.currency.renderBases.A1 | type' "$MAN")"
assert_eq "T3-renderBases.A2 object"  "object" "$(jq -r '.currency.renderBases.A2 | type' "$MAN")"
assert_eq "T3-hooks object"           "object" "$(jq -r '.currency.hooks | type' "$MAN")"
assert_eq "T3-mcpProbe.context7 present-or-absent" "true" \
  "$(jq -r '(.currency.mcpProbe.context7 == "present") or (.currency.mcpProbe.context7 == "absent")' "$MAN")"
# Top-level keys are EXACTLY the six from the schema.
assert_eq "T3-currency has exactly the 6 schema keys" \
  "files hooks mcpProbe renderBases schemaVersion soloFrameworkPath" \
  "$(jq -r '.currency | keys | join(" ")' "$MAN")"

# ════════════════════════════════════════════════════════════════════════════
# T4 — class assignment on the fixture tree
# ════════════════════════════════════════════════════════════════════════════
echo "== T4: class assignment =="
assert_eq "T4-script alpha.sh -> M"                 "M"  "$(soif_currency_file_field "$MAN" "scripts/alpha.sh" class)"
assert_eq "T4-hook lib -> M"                        "M"  "$(soif_currency_file_field "$MAN" "scripts/lib/hook-templates.sh" class)"
assert_eq "T4-glob host-driver -> M"                "M"  "$(soif_currency_file_field "$MAN" "scripts/host-drivers/github.driver.sh" class)"
assert_eq "T4-reference doc -> T"                   "T"  "$(soif_currency_file_field "$MAN" "docs/reference/builders-guide.md" class)"
assert_eq "T4-skill SKILL.md -> M"                  "M"  "$(soif_currency_file_field "$MAN" ".claude/skills/alpha-skill/SKILL.md" class)"
assert_eq "T4-skill NOTICE -> M"                    "M"  "$(soif_currency_file_field "$MAN" ".claude/skills/alpha-skill/NOTICE" class)"
assert_eq "T4-CLAUDE.md -> A1"                      "A1" "$(soif_currency_file_field "$MAN" "CLAUDE.md" class)"
assert_eq "T4-PROJECT_INTAKE.md -> A1"              "A1" "$(soif_currency_file_field "$MAN" "PROJECT_INTAKE.md" class)"
# beta-skill has no NOTICE in source: mechanical derivation must NOT invent one.
assert_eq "T4-beta NOTICE absent (source has none)" "" \
  "$(jq -r '.currency.files[".claude/skills/beta-skill/NOTICE"] // "" | if . == "" then "" else "PRESENT" end' "$MAN")"
assert_eq "T4-beta SKILL.md present"                "M"  "$(soif_currency_file_field "$MAN" ".claude/skills/beta-skill/SKILL.md" class)"
# A2 agent-authored artifacts are NOT in files{} (they do not exist at birth).
assert_eq "T4-PROJECT_BIBLE.md not in files{}"      "null" "$(jq -r '.currency.files["PROJECT_BIBLE.md"] // "null"' "$MAN")"
assert_eq "T4-PRODUCT_MANIFESTO.md not in files{}"  "null" "$(jq -r '.currency.files["PRODUCT_MANIFESTO.md"] // "null"' "$MAN")"

# ════════════════════════════════════════════════════════════════════════════
# T5 — sha/mode in files{} match independent recomputation; state == "current"
# ════════════════════════════════════════════════════════════════════════════
echo "== T5: files{} sha/mode fidelity + state =="
recomputed_ok=1
for rel in scripts/alpha.sh scripts/lib/hook-templates.sh \
           scripts/host-drivers/github.driver.sh docs/reference/builders-guide.md \
           .claude/skills/alpha-skill/SKILL.md .claude/skills/alpha-skill/NOTICE \
           .claude/skills/beta-skill/SKILL.md CLAUDE.md PROJECT_INTAKE.md; do
  exp="$(shasum -a 256 "$PROJ/$rel" | awk '{print $1}')"
  got="$(soif_currency_file_field "$MAN" "$rel" sha256)"
  [ "$exp" = "$got" ] || { recomputed_ok=0; echo "    mismatch: $rel exp=$exp got=$got"; }
done
if [ "$recomputed_ok" -eq 1 ]; then pass "T5-every files{} sha256 recomputes"; else fail "T5-every files{} sha256 recomputes" "see mismatches"; fi
# state:"current" on every entry.
non_current="$(jq -r '[.currency.files[] | select(.state != "current")] | length' "$MAN")"
assert_eq "T5-every files{} entry state == current" "0" "$non_current"
# mode present on every entry.
no_mode="$(jq -r '[.currency.files[] | select(.mode == null or .mode == "")] | length' "$MAN")"
assert_eq "T5-every files{} entry has a mode" "0" "$no_mode"

# ════════════════════════════════════════════════════════════════════════════
# T6 — render bases captured at render site (A1 template+output, A2 template-only)
# ════════════════════════════════════════════════════════════════════════════
echo "== T6: render bases =="
exp_tmpl="$(shasum -a 256 "$FW/templates/generated/claude-md.tmpl" | awk '{print $1}')"
exp_out="$(shasum -a 256 "$PROJ/CLAUDE.md" | awk '{print $1}')"
assert_eq "T6-A1 CLAUDE.md templateSha recomputes" "$exp_tmpl" "$(jq -r '.currency.renderBases.A1["CLAUDE.md"].templateSha' "$MAN")"
assert_eq "T6-A1 CLAUDE.md outputSha recomputes"   "$exp_out"  "$(jq -r '.currency.renderBases.A1["CLAUDE.md"].outputSha' "$MAN")"
# The A1 files{} sha256 == the render-base outputSha (captured once, never re-hashed post-hoc).
assert_eq "T6-A1 files sha == render outputSha" \
  "$(jq -r '.currency.renderBases.A1["CLAUDE.md"].outputSha' "$MAN")" \
  "$(soif_currency_file_field "$MAN" "CLAUDE.md" sha256)"
exp_bible="$(shasum -a 256 "$FW/templates/generated/project-bible.tmpl" | awk '{print $1}')"
assert_eq "T6-A2 PROJECT_BIBLE templateSha recomputes" "$exp_bible" "$(jq -r '.currency.renderBases.A2["PROJECT_BIBLE.md"].templateSha' "$MAN")"
# A2 records template ONLY — no outputSha key.
assert_eq "T6-A2 has no outputSha" "null" "$(jq -r '.currency.renderBases.A2["PROJECT_BIBLE.md"].outputSha // "null"' "$MAN")"

# ════════════════════════════════════════════════════════════════════════════
# T7 — hooks block value + reader/writer round-trip + additive merge
# ════════════════════════════════════════════════════════════════════════════
echo "== T7: hooks value + round-trip + additive =="
assert_eq "T7-commit-msg present (typescript fixture)" "present" "$(jq -r '.currency.hooks["commit-msg"]' "$MAN")"
assert_eq "T7-pre-commit present"                      "present" "$(jq -r '.currency.hooks["pre-commit"]' "$MAN")"
assert_eq "T7-reader round-trip (hook)" "present" "$(soif_currency_read "$MAN" '.currency.hooks["commit-msg"]')"
assert_eq "T7-reader round-trip (file sha)" \
  "$(shasum -a 256 "$PROJ/scripts/alpha.sh" | awk '{print $1}')" \
  "$(soif_currency_file_field "$MAN" "scripts/alpha.sh" sha256)"
# Additive: pre-existing pins/fields survive untouched.
assert_eq "T7-additive: host preserved"               "github"   "$(jq -r '.host' "$MAN")"
assert_eq "T7-additive: soloFrameworkCommit preserved" "deadbeef" "$(jq -r '.soloFrameworkCommit' "$MAN")"
assert_eq "T7-additive: frameworkCommit preserved"     "cafef00d" "$(jq -r '.frameworkCommit' "$MAN")"

# A rust fixture stamps absent-intentional (fresh manifest, no re-render needed).
MAN2="$TOPTMP/rust-manifest.json"
printf '{"host":"gitlab"}\n' > "$MAN2"
SOIF_CURRENCY_RENDERBASE_FILE="" soif_currency_stamp "$MAN2" "$FW/init.sh" "$FW" "$PROJ" rust "$FW"
# BL-107-UNIVERSAL-INSTALL: rust/other manifests now stamp present (the gate
# ships for every language); the absent-* values remain reader-side legacy.
assert_eq "T7-rust fixture -> commit-msg present (BL-107)" "present" "$(jq -r '.currency.hooks["commit-msg"]' "$MAN2")"
# An `other`-language fixture also stamps present since BL-107.
MAN3="$TOPTMP/other-manifest.json"
printf '{"host":"gitlab"}\n' > "$MAN3"
SOIF_CURRENCY_RENDERBASE_FILE="" soif_currency_stamp "$MAN3" "$FW/init.sh" "$FW" "$PROJ" other "$FW"
assert_eq "T7-other fixture -> commit-msg present (BL-107)" "present" "$(jq -r '.currency.hooks["commit-msg"]' "$MAN3")"

# ════════════════════════════════════════════════════════════════════════════
# T8 — dual-source ban (review-r1 B2): no product-code second-manifest filename
# ════════════════════════════════════════════════════════════════════════════
echo "== T8: dual-source ban =="
# Build the forbidden standalone-manifest filename from parts so THIS test file
# does not itself contain the literal token it bans (self-reference trap).
ban_token="framework""-manifest"
ban_hits="$(grep -rl "$ban_token" "$REPO_ROOT/scripts" "$REPO_ROOT/tests" "$REPO_ROOT/init.sh" 2>/dev/null | wc -l | tr -d ' ')"
case "$ban_hits" in ''|*[!0-9]*) ban_hits=0 ;; esac
assert_eq "T8-no standalone-manifest filename in product code" "0" "$ban_hits"
# The stamp writes exactly one manifest file — never a sibling.
sibling="$(find "$PROJ/.claude" -maxdepth 1 -name '*manifest*.json' | wc -l | tr -d ' ')"
case "$sibling" in ''|*[!0-9]*) sibling=0 ;; esac
assert_eq "T8-exactly one manifest file in .claude/" "1" "$sibling"

# ════════════════════════════════════════════════════════════════════════════
# T9 — files{} is hashed in ONE batch (`# BL-337-BATCH-HASH`)
# ════════════════════════════════════════════════════════════════════════════
# Per-file shasum + stat cost ~1.2 s per block over an adopted project, and an
# adoption builds the block twice (rehearsal + real). The batch must give every
# row exactly what the per-file soif_currency_sha256 / soif_currency_mode give
# that file under the same PATH, keep the shasum -> sha256sum -> refuse order
# (`# BL-337-SHA256-FALLBACK`), and fail loud rather than mis-pair.
#
# The project path carries a space and a backslash: shasum and GNU sha256sum
# answer a backslash in a name by escaping it and prefixing the line with `\`.
#
# Every tool is reached through a bin folder holding only what the block runs,
# so a hasher can be wrapped (counted, broken) or left out. A tool missing from
# that list fails T9a's positive control, never passes silently.
echo "== T9: batched hashing =="
PROJB="$TOPTMP/proj b\\x"
cp -R "$PROJ" "$PROJB"
chmod 750 "$PROJB/scripts/alpha.sh"
T9_ROWS="scripts/alpha.sh M
scripts/host-drivers/github.driver.sh M
scripts/lib/hook-templates.sh M
.claude/skills/alpha-skill/NOTICE M
.claude/skills/alpha-skill/SKILL.md M
.claude/skills/beta-skill/SKILL.md M
docs/reference/builders-guide.md T"
REAL_SHASUM="$(command -v shasum 2>/dev/null)"
REAL_SHA256SUM="$(command -v sha256sum 2>/dev/null)"
T9_LOG="$TOPTMP/t9-calls.log"
# t9_bin <dir> <hasher...> — a bin folder of the block's own tools plus the
# named hashers. `shasum`, `sha256sum` and `stat` log one line per invocation;
# `shasum:drop|:extra|:nothex|:rc1`, `stat:drop` and `awk:busybox|:failprefix` lie in that way.
t9_bin() {
  local dir="$1" t="" p="" h="" st="" ra=""; shift
  mkdir -p "$dir"
  for t in jq sed sort grep basename head cat tr; do
    p="$(command -v "$t" 2>/dev/null)" && ln -s "$p" "$dir/$t"
  done
  # awk is always a wrapper: it passes through, or (`awk:busybox`) refuses the
  # bare `length` pattern the way busybox does, or (`awk:failprefix`) exits 3 on
  # any program that starts with `length`, the block's CANDIDATES prefixer.
  ra="$(command -v awk)"
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$ra" > "$dir/awk"
  st="$(command -v stat)"
  printf '#!/bin/sh\necho stat >> "%s"\nexec "%s" "$@"\n' "$T9_LOG" "$st" > "$dir/stat"
  for h in "$@"; do
    case "$h" in
      stat:drop)     printf '#!/bin/sh\n"%s" "$@" | sed '"'"'$d'"'"'\n' "$st" > "$dir/stat" ;;
      shasum)        printf '#!/bin/sh\necho shasum >> "%s"\nexec "%s" "$@"\n' "$T9_LOG" "$REAL_SHASUM" > "$dir/shasum" ;;
      shasum:drop)   printf '#!/bin/sh\n"%s" "$@" | sed '"'"'$d'"'"'\n' "$REAL_SHASUM" > "$dir/shasum" ;;
      shasum:extra)  printf '#!/bin/sh\n"%s" "$@" | sed '"'"'1p'"'"'\n' "$REAL_SHASUM" > "$dir/shasum" ;;
      awk:busybox)   printf '#!/bin/sh\nfor a in "$@"; do\n  case "$a" in '"'"'length {'"'"'*|'"'"'length{'"'"'*) echo "awk: cmd. line:1: Unexpected token" >&2; exit 1 ;; esac\ndone\nexec "%s" "$@"\n' "$ra" > "$dir/awk" ;;
      awk:failprefix) printf '#!/bin/sh\nfor a in "$@"; do\n  case "$a" in length*) exit 3 ;; esac\ndone\nexec "%s" "$@"\n' "$ra" > "$dir/awk" ;;
      shasum:nothex) printf '#!/bin/sh\n"%s" "$@" | sed '"'"'1s/[0-9a-f]/z/'"'"'\n' "$REAL_SHASUM" > "$dir/shasum" ;;
      shasum:rc1)    printf '#!/bin/sh\n"%s" "$@"\nexit 1\n' "$REAL_SHASUM" > "$dir/shasum" ;;
      sha256sum)
        if [ -n "$REAL_SHA256SUM" ]; then p="exec \"$REAL_SHA256SUM\" \"\$@\""; else p="exec \"$REAL_SHASUM\" -a 256 \"\$@\""; fi
        printf '#!/bin/sh\necho sha256sum >> "%s"\n%s\n' "$T9_LOG" "$p" > "$dir/sha256sum" ;;
    esac
  done
  for t in stat awk shasum sha256sum; do   # the wrappers only, never a symlinked tool
    if [ -f "$dir/$t" ] && [ ! -L "$dir/$t" ]; then chmod +x "$dir/$t"; fi
  done
}
# t9_expected <bindir> — files{} built one file at a time with the per-file
# soif_currency_sha256 / soif_currency_mode, under the same PATH, sorted.
t9_expected() {
  ( PATH="$1"
    printf '%s\n' "$T9_ROWS" | while read -r rel cls; do
      printf '%s\t%s\t%s\t%s\n' "$rel" "$(soif_currency_sha256 "$PROJB/$rel")" "$(soif_currency_mode "$PROJB/$rel")" "$cls"
    done | jq -SRn '[inputs | split("\t") | {(.[0]): {sha256: .[1], mode: .[2], class: .[3], state: "current"}}] | add' )
}
# t9_run <bindir> [project] — the block on PROJB (or [project]) with only
# <bindir> on PATH; sets T9_RC, T9_OUT (stdout), T9_ERR (stderr) and T9_FILES
# (its files{}, sorted).
t9_run() {
  : > "$T9_LOG"
  T9_RC=0
  ( PATH="$1"; soif_currency_block "$FW/init.sh" "$FW" "${2:-$PROJB}" typescript "$FW" "unknown:t9" ) \
    > "$TOPTMP/t9.out" 2> "$TOPTMP/t9.err" || T9_RC=$?
  T9_OUT="$(cat "$TOPTMP/t9.out")"; T9_ERR="$(cat "$TOPTMP/t9.err")"
  T9_FILES="$(printf '%s' "$T9_OUT" | jq -S '.files' 2>/dev/null)"
  T9_ORDER="$(printf '%s' "$T9_OUT" | jq -r '.files | keys_unsorted | join(" ")' 2>/dev/null)"
}
t9_calls() { command grep -c "^$1\$" "$T9_LOG" 2>/dev/null; }
t9_short() { printf '%s' "$1" | tr '\n' ' ' | cut -c1-160; }
# t9_refused <label> <stderr-pattern> — the block failed, printed no block, and said why.
t9_refused() {
  if [ "$T9_RC" -ne 0 ] && [ -z "$T9_OUT" ] && printf '%s' "$T9_ERR" | command grep -q -- "$2"; then pass "$1"
  else fail "$1" "rc $T9_RC, out [$(t9_short "$T9_OUT")], err [$(t9_short "$T9_ERR")]"; fi
}

if [ -z "$REAL_SHASUM" ]; then
  fail "T9 batched hashing" "shasum is not on PATH; the wrappers need it"
else
  t9_bin "$TOPTMP/t9-shasum" shasum sha256sum
  want="$(t9_expected "$TOPTMP/t9-shasum")"
  t9_run "$TOPTMP/t9-shasum"
  # jq keeps insertion order, so the rows' order is part of the block's bytes.
  want_order="$(printf '%s\n' "$T9_ROWS" | awk '{print $1}' | tr '\n' ' ' | sed 's/ $//')"
  if [ "$T9_RC" -eq 0 ] && [ "$(printf '%s' "$T9_FILES" | jq 'length')" = "7" ] && [ "$T9_FILES" = "$want" ] && [ "$T9_ORDER" = "$want_order" ]; then
    pass "T9a all 7 files{} rows equal the per-file sha256 + mode, in parser order, under a path with a space and a backslash"
  else
    fail "T9a all 7 files{} rows equal the per-file sha256 + mode, in parser order, under a path with a space and a backslash" \
      "rc $T9_RC, err [$(t9_short "$T9_ERR")], order [$T9_ORDER], got $(printf '%s' "$T9_FILES" | jq -c . 2>/dev/null), want $(printf '%s' "$want" | jq -c .)"
  fi
  # Seven files: ONE shasum, and stat at most twice (GNU -c, then BSD -f).
  if [ "$(t9_calls shasum)" = "1" ] && [ "$(t9_calls sha256sum)" = "0" ] && [ "$(t9_calls stat)" -le 2 ]; then
    pass "T9b seven files take one shasum and at most two stat processes"
  else
    fail "T9b seven files take one shasum and at most two stat processes" \
      "shasum=$(t9_calls shasum) sha256sum=$(t9_calls sha256sum) stat=$(t9_calls stat)"
  fi
  t9_bin "$TOPTMP/t9-sha256sum" sha256sum
  want="$(t9_expected "$TOPTMP/t9-sha256sum")"
  t9_run "$TOPTMP/t9-sha256sum"
  if [ "$T9_RC" -eq 0 ] && [ "$(printf '%s' "$T9_FILES" | jq 'length')" = "7" ] && [ "$T9_FILES" = "$want" ] && [ "$(t9_calls sha256sum)" = "1" ]; then
    pass "T9c with sha256sum and no shasum, one sha256sum gives every row its per-file hash"
  else
    fail "T9c with sha256sum and no shasum, one sha256sum gives every row its per-file hash" \
      "rc $T9_RC, sha256sum=$(t9_calls sha256sum), err [$(t9_short "$T9_ERR")], got $(printf '%s' "$T9_FILES" | jq -c . 2>/dev/null), want $(printf '%s' "$want" | jq -c .)"
  fi
  t9_bin "$TOPTMP/t9-none"
  t9_run "$TOPTMP/t9-none"
  t9_refused "T9d with neither hasher the block is rc 1 with a message, not an empty files{}" 'neither shasum nor sha256sum'
  t9_bin "$TOPTMP/t9-drop" shasum:drop
  t9_run "$TOPTMP/t9-drop"
  t9_refused "T9e a hasher that returns one line too few fails loud, never mis-pairs" '6 hash line(s) for 7 file(s)'
  t9_bin "$TOPTMP/t9-extra" shasum:extra
  t9_run "$TOPTMP/t9-extra"
  t9_refused "T9f a hasher that returns one line too many fails loud, never mis-pairs" '8 hash line(s) for 7 file(s)'
  t9_bin "$TOPTMP/t9-nothex" shasum:nothex
  t9_run "$TOPTMP/t9-nothex"
  t9_refused "T9g a line whose first field is not a sha256 fails loud" 'not a sha256'
  t9_bin "$TOPTMP/t9-rc1" shasum:rc1
  t9_run "$TOPTMP/t9-rc1"
  t9_refused "T9h a hasher that exits non-zero (an unreadable file) fails loud even with full output" 'shasum failed'
  t9_bin "$TOPTMP/t9-statdrop" shasum stat:drop
  t9_run "$TOPTMP/t9-statdrop"
  t9_refused "T9i a stat that returns too few mode lines fails loud, never mis-pairs" 'mode line(s) for 7 file(s)'
  # A shipped file the project does not hold is skipped, as it always was.
  PROJC="$TOPTMP/proj c"
  cp -R "$PROJB" "$PROJC" && mv "$PROJC/.claude/skills/beta-skill/SKILL.md" "$TOPTMP/t9-moved-SKILL.md"
  t9_run "$TOPTMP/t9-shasum" "$PROJC"
  if [ "$T9_RC" -eq 0 ] && [ "$(printf '%s' "$T9_FILES" | jq 'length')" = "6" ] \
     && [ "$(printf '%s' "$T9_FILES" | jq 'has(".claude/skills/beta-skill/SKILL.md")')" = "false" ]; then
    pass "T9j a shipped file missing from the project is skipped, and the other six are hashed"
  else
    fail "T9j a shipped file missing from the project is skipped, and the other six are hashed" "rc $T9_RC, err [$(t9_short "$T9_ERR")], rows [$T9_ORDER]"
  fi
  # busybox awk (Alpine) rejects a bare `length` pattern. The candidate list is
  # built with awk, so a program it cannot parse must neither be written that way
  # nor pass silently: Alpine once recorded NO M/T rows with rc 0 (main 107 rows).
  t9_bin "$TOPTMP/t9-busybox" shasum awk:busybox
  want="$(t9_expected "$TOPTMP/t9-busybox")"
  t9_run "$TOPTMP/t9-busybox"
  if [ "$T9_RC" -eq 0 ] && [ "$(printf '%s' "$T9_FILES" | jq 'length')" = "7" ] && [ "$T9_FILES" = "$want" ]; then
    pass "T9k an awk that rejects a bare \`length\` pattern (busybox) still gives all 7 rows"
  else
    fail "T9k an awk that rejects a bare \`length\` pattern (busybox) still gives all 7 rows" \
      "rc $T9_RC, err [$(t9_short "$T9_ERR")], rows [$T9_ORDER]"
  fi
  t9_bin "$TOPTMP/t9-awkfail" shasum awk:failprefix
  t9_run "$TOPTMP/t9-awkfail"
  t9_refused "T9l an awk that fails building the candidate list is rc 1 with a message, never rc 0 with no rows" 'awk failed'
  # Nothing to hash is legitimate (n=0): rc 0, no rows, and the hasher is never
  # started, since `shasum -a 256` with no file arguments reads STDIN. A pipe
  # carrying data proves it: the data must still be there afterwards.
  PROJD="$TOPTMP/proj d"; mkdir -p "$PROJD"
  : > "$TOPTMP/t9m.rest"
  printf 'ANSWER\n' | {
    ( PATH="$TOPTMP/t9-shasum"; _soif_currency_mt_files_tsv "$FW/init.sh" "$FW" "$PROJD" ) > "$TOPTMP/t9m.out" 2> "$TOPTMP/t9m.err"
    echo "$?" > "$TOPTMP/t9m.rc"
    cat > "$TOPTMP/t9m.rest"
  }
  if [ "$(cat "$TOPTMP/t9m.rc")" = "0" ] && [ ! -s "$TOPTMP/t9m.out" ] && [ ! -s "$TOPTMP/t9m.err" ] && [ "$(cat "$TOPTMP/t9m.rest")" = "ANSWER" ]; then
    pass "T9m a project holding none of the shipped files gives no rows, rc 0, and leaves stdin unread"
  else
    fail "T9m a project holding none of the shipped files gives no rows, rc 0, and leaves stdin unread" \
      "rc $(cat "$TOPTMP/t9m.rc"), out [$(t9_short "$(cat "$TOPTMP/t9m.out")")], err [$(t9_short "$(cat "$TOPTMP/t9m.err")")], stdin left [$(t9_short "$(cat "$TOPTMP/t9m.rest")")]"
  fi
  # init.sh stamps with project dir "."; the no-hasher message must name where
  # that is, and the remedy, not "under .".
  T9_CWD="$PWD"; cd "$PROJB" || exit 1
  t9_run "$TOPTMP/t9-none" .
  T9_HERE="$PWD"; cd "$T9_CWD" || exit 1
  case "$T9_ERR" in
    *"under $T9_HERE"*"shasum (perl)"*"sha256sum (coreutils)"*) pass "T9n the no-hasher message names the absolute project dir and the tools to install" ;;
    *) fail "T9n the no-hasher message names the absolute project dir and the tools to install" "rc $T9_RC, err [$(t9_short "$T9_ERR")], want dir [$T9_HERE]" ;;
  esac
fi

# ── Tally ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

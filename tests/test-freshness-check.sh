#!/usr/bin/env bash
# tests/test-freshness-check.sh
#
# BL-109 SLICE-S2 (Currency System, Layer 1 — Detection) UNIT LANE.
#
# Exercises scripts/session-freshness-check.sh + scripts/lib/freshness-detect.sh
# entirely through hand-built fixture manifests + fixture framework/CDF trees —
# NEVER init.sh (that fidelity proof is the aggregator, tests/test-freshness-
# birth.sh). Because it does not execute init.sh it is ALSO in the tests.yml
# unit fast lane.
#
# Coverage (design v1.1 §2-L1 + I7 + review-r1 M5/M6/M9):
#   • silence-when-current — ZERO bytes on stdout AND stderr, exit 0
#   • every drift class → the right tier (local-edit/fw-drift-gate/fw-drift-non-
#     gate/orphan/hook-drift/hook-missing/hook-unavailable/render-base/cdf)
#   • hooks expectation enum: absent-intentional silent; absent-unavailable
#     enforcement (BL-107)
#   • pin-absent + path-missing → framework checks skip SILENTLY (BL-110 interim)
#   • torn cache → cold start, never fatal
#   • future-timestamp snooze clamp → treated expired (item re-surfaces)
#   • snooze hold/expiry boundaries (6-day held, 8-day expired) + informational
#     delta-change void + standing "N enforcement items snoozed" line (M5)
#   • machine-block JSON validity + key stability
#   • exit 0 under an injected crash (fail-open, I7)
#   • --snooze records an enforcement snooze through bypass-audit.sh (M5)
#
# Hermetic: mktemp, git identity set in fixtures, GITHUB_BASE_REF unset,
# CDF_HOME pointed at a nonexistent path (no live remotes). bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUT="$REPO_ROOT/scripts/session-freshness-check.sh"
HOOKTPL="$REPO_ROOT/scripts/lib/hook-templates.sh"

unset GITHUB_BASE_REF 2>/dev/null || true

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  echo "SKIP: jq/git required"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

TOP="$(mktemp -d)"
trap 'rm -rf "$TOP"' EXIT
NCASE=0

# sha <file>
sha() { shasum -a 256 "$1" | awk '{print $1}'; }

# build_fw <dir> — a fresh framework git checkout with a known shipped surface:
#   scripts/validate.sh          (non-gate M)
#   scripts/pre-commit-gate.sh   (gate M → enforcement tier)
#   scripts/lib/hook-templates.sh (copied from the repo; drives hook currency)
#   templates/generated/claude-md.tmpl (render-base A1)
#   docs/builders-guide.md       (reference-doc T source)
#   init.sh stub (reference-doc source mapping)
# Sets globals FW + PIN (never echoes — a stray git message must not corrupt the
# capture; git output is silenced for the same reason).
FW=""; PIN=""
build_fw() {
  local fw="$1"
  mkdir -p "$fw/scripts/lib" "$fw/templates/generated" "$fw/docs"
  printf 'echo validate v1\n'            > "$fw/scripts/validate.sh"
  printf 'echo gate v1\n'                > "$fw/scripts/pre-commit-gate.sh"
  cp "$HOOKTPL"                            "$fw/scripts/lib/hook-templates.sh"
  printf 'CLAUDE template v1\n'          > "$fw/templates/generated/claude-md.tmpl"
  printf 'builders guide v1\n'          > "$fw/docs/builders-guide.md"
  printf 'cp "$SCRIPT_DIR/docs/builders-guide.md" docs/reference/\n' > "$fw/init.sh"
  git -C "$fw" init -q >/dev/null 2>&1
  git -C "$fw" config user.email t@t.t
  git -C "$fw" config user.name  tester
  git -C "$fw" add -A >/dev/null 2>&1
  git -C "$fw" commit -qm "fw v1" >/dev/null 2>&1
  FW="$fw"
  PIN="$(git -C "$fw" rev-parse HEAD 2>/dev/null)"
}

# build_proj_current <projdir> <fwdir> <pin> — a project whose manifest currency
# block is fully CURRENT against <fwdir>@<pin>: tracked files match, hooks
# installed + current, render base matches, pin present.
build_proj_current() {
  local proj="$1" fw="$2" pin="$3"
  mkdir -p "$proj/.claude" "$proj/scripts/lib" "$proj/docs/reference" "$proj/.git/hooks"
  cp "$fw/scripts/validate.sh"          "$proj/scripts/validate.sh"
  cp "$fw/scripts/pre-commit-gate.sh"   "$proj/scripts/pre-commit-gate.sh"
  cp "$fw/docs/builders-guide.md"       "$proj/docs/reference/builders-guide.md"
  # install current hooks from the framework templates
  ( . "$HOOKTPL"; soif_write_precommit_hook "$proj/.git/hooks/pre-commit" )
  { printf '#!/usr/bin/env bash\n'; ( . "$HOOKTPL"; soif_emit_tdd_commitmsg_block ); } > "$proj/.git/hooks/commit-msg"
  local v_sha g_sha d_sha tpl_sha cm_block
  v_sha="$(sha "$fw/scripts/validate.sh")"
  g_sha="$(sha "$fw/scripts/pre-commit-gate.sh")"
  d_sha="$(sha "$fw/docs/builders-guide.md")"
  tpl_sha="$(sha "$fw/templates/generated/claude-md.tmpl")"
  jq -n --arg pin "$pin" --arg fw "$fw" \
        --arg v "$v_sha" --arg g "$g_sha" --arg d "$d_sha" --arg tpl "$tpl_sha" '{
    soloFrameworkCommit:$pin,
    frameworkCommit:"cdfpinabc",
    currency:{
      schemaVersion:1, soloFrameworkPath:$fw,
      files:{
        "scripts/validate.sh":{sha256:$v, mode:"755", class:"M", state:"current"},
        "scripts/pre-commit-gate.sh":{sha256:$g, mode:"755", class:"M", state:"current"},
        "docs/reference/builders-guide.md":{sha256:$d, mode:"644", class:"T", state:"current"}
      },
      renderBases:{ A1:{ "CLAUDE.md":{templateSha:$tpl, outputSha:"deadbeef"} }, A2:{} },
      hooks:{ "pre-commit":"present", "commit-msg":"present" },
      mcpProbe:{context7:"absent"}
    }
  }' > "$proj/.claude/manifest.json"
}

# run <projdir> — invoke the SUT; captures stdout to $OUT, stderr to $ERR,
# exit to $RC. CDF defaults to a nonexistent clone (silent). Extra env is
# inherited from the caller (SOIF_FRESHNESS_NOW etc.).
OUT=""; ERR=""; RC=0
run() {
  local proj="$1"
  OUT="$(CDF_HOME="${CDF_HOME:-$TOP/no-cdf}" CLAUDE_PROJECT_DIR="$proj" bash "$SUT" 2>"$TOP/err.$$")"
  RC=$?
  ERR="$(cat "$TOP/err.$$")"
  rm -f "$TOP/err.$$"
}

newdir() { NCASE=$((NCASE + 1)); echo "$TOP/c$NCASE"; }

# ════════════════════════════════════════════════════════════════════════════
echo "=== silence-when-current: zero bytes stdout+stderr, exit 0 ==="
D="$(newdir)"; build_fw "$D/fw"; build_proj_current "$D/proj" "$FW" "$PIN"
run "$D/proj"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; then
  pass "current scaffold is byte-silent on stdout+stderr, exit 0"
else
  fail_ "silence-when-current" "rc=$RC stdout=[$OUT] stderr=[$ERR]"
fi
# warm cache written under .claude/cache/ only
if [ -f "$D/proj/.claude/cache/freshness.json" ] && jq -e . "$D/proj/.claude/cache/freshness.json" >/dev/null 2>&1; then
  pass "warm cache written + valid JSON at .claude/cache/freshness.json"
else
  fail_ "warm cache" "cache missing or invalid"
fi

# ════════════════════════════════════════════════════════════════════════════
echo "=== local-edit → informational ==="
D="$(newdir)"; build_fw "$D/fw"; build_proj_current "$D/proj" "$FW" "$PIN"
printf 'echo locally edited\n' > "$D/proj/scripts/validate.sh"
run "$D/proj"
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -qi 'archive-and-replace' \
   && printf '%s' "$OUT" | grep -q 'Informational:'; then
  pass "local edit surfaces as an informational archive-and-replace warning"
else
  fail_ "local-edit" "rc=$RC out=[$OUT]"
fi

# ════════════════════════════════════════════════════════════════════════════
echo "=== framework drift on a GATE script → enforcement ==="
D="$(newdir)"; build_fw "$D/fw"; build_proj_current "$D/proj" "$FW" "$PIN"
printf 'echo gate v2 upstream\n' > "$FW/scripts/pre-commit-gate.sh"
git -C "$FW" add -A >/dev/null 2>&1; git -C "$FW" commit -qm "gate bump" >/dev/null 2>&1
run "$D/proj"
mach="$(printf '%s' "$OUT" | sed -n '/```soif-freshness/,/```/p' | sed '1d;$d')"
tier="$(printf '%s' "$mach" | jq -r '.items[] | select(.id=="fw-drift:scripts/pre-commit-gate.sh") | .tier' 2>/dev/null)"
if [ "$tier" = "enforcement" ] && printf '%s' "$OUT" | grep -q 'Recommended now (enforcement):'; then
  pass "gate-script framework drift is ENFORCEMENT tier"
else
  fail_ "fw-drift-gate" "tier=[$tier] out=[$OUT]"
fi

# ════════════════════════════════════════════════════════════════════════════
echo "=== framework drift on a NON-gate script → informational ==="
D="$(newdir)"; build_fw "$D/fw"; build_proj_current "$D/proj" "$FW" "$PIN"
printf 'echo validate v2 upstream\n' > "$FW/scripts/validate.sh"
git -C "$FW" add -A >/dev/null 2>&1; git -C "$FW" commit -qm "validate bump" >/dev/null 2>&1
run "$D/proj"
mach="$(printf '%s' "$OUT" | sed -n '/```soif-freshness/,/```/p' | sed '1d;$d')"
tier="$(printf '%s' "$mach" | jq -r '.items[] | select(.id=="fw-drift:scripts/validate.sh") | .tier' 2>/dev/null)"
[ "$tier" = "informational" ] && pass "non-gate framework drift is informational" \
  || fail_ "fw-drift-nongate" "tier=[$tier] out=[$OUT]"

# ════════════════════════════════════════════════════════════════════════════
echo "=== orphan (upstream source deleted) → enforcement ==="
D="$(newdir)"; build_fw "$D/fw"; build_proj_current "$D/proj" "$FW" "$PIN"
git -C "$FW" rm -q "scripts/validate.sh" >/dev/null 2>&1; rm -f "$FW/scripts/validate.sh"
git -C "$FW" commit -qm "delete validate" >/dev/null 2>&1
run "$D/proj"
mach="$(printf '%s' "$OUT" | sed -n '/```soif-freshness/,/```/p' | sed '1d;$d')"
otier="$(printf '%s' "$mach" | jq -r '.items[] | select(.id=="orphan:scripts/validate.sh") | .tier' 2>/dev/null)"
overb="$(printf '%s' "$mach" | jq -r '.items[] | select(.id=="orphan:scripts/validate.sh") | .verb' 2>/dev/null)"
if [ "$otier" = "enforcement" ] && [ "$overb" = "retire" ]; then
  pass "orphaned tracked file is ENFORCEMENT tier with verb=retire"
else
  fail_ "orphan" "tier=[$otier] verb=[$overb] out=[$OUT]"
fi

# ════════════════════════════════════════════════════════════════════════════
# BL-109 S3 review round 3 (minor 1). The drift arm compared the MANIFEST sha to the
# UPSTREAM sha and never checked that the project file still EXISTS, so a tracked gate
# script the operator had DELETED locally surfaced as ordinary framework-drift with verb
# `update` — a diff with no base. Downstream (S3 --plan) that empty payload tripped the
# fail-closed I11 guard and aborted the WHOLE plan, blaming the payload and the verb
# instead of the missing file. The condition is now detected and NAMED (# BL-109-MISSING):
# still shipped upstream → offered back (verb `add`, a real /dev/null → upstream diff);
# gone upstream too → a stale manifest entry with nothing to apply (verb `untrack`).
echo "=== tracked file MISSING from the project → named, not misdiagnosed as drift (BL-109-MISSING) ==="
D="$(newdir)"; build_fw "$D/fw"; build_proj_current "$D/proj" "$FW" "$PIN"
# drift the gate script upstream too — the pre-fix code reported THAT and hid the deletion
printf 'echo gate v2\n' > "$FW/scripts/pre-commit-gate.sh"
git -C "$FW" add -A >/dev/null 2>&1; git -C "$FW" commit -qm "gate v2" >/dev/null 2>&1
rm -f "$D/proj/scripts/pre-commit-gate.sh"          # tracked GATE script, deleted locally
run "$D/proj"
mach="$(printf '%s' "$OUT" | sed -n '/```soif-freshness/,/```/p' | sed '1d;$d')"
mtier="$(printf '%s' "$mach" | jq -r '.items[] | select(.id=="missing:scripts/pre-commit-gate.sh") | .tier' 2>/dev/null)"
mverb="$(printf '%s' "$mach" | jq -r '.items[] | select(.id=="missing:scripts/pre-commit-gate.sh") | .verb' 2>/dev/null)"
mmsg="$(printf '%s' "$mach" | jq -r '.items[] | select(.id=="missing:scripts/pre-commit-gate.sh") | .message' 2>/dev/null)"
ndrift="$(printf '%s' "$mach" | jq -r '[.items[] | select(.id=="fw-drift:scripts/pre-commit-gate.sh")] | length' 2>/dev/null)"
if [ "$mtier" = "enforcement" ] && [ "$mverb" = "add" ] && [ "$ndrift" = "0" ] \
   && printf '%s' "$mmsg" | grep -q 'tracked file is missing from the project'; then
  pass "a locally-deleted tracked GATE script is reported as MISSING (enforcement, verb=add, restorable) — never as framework-drift"
else
  fail_ "missing tracked file" "tier=[$mtier] verb=[$mverb] fw-drift-rows=[$ndrift] msg=[$mmsg]"
fi

# …and when it is gone UPSTREAM too, there is nothing to restore and nothing to retire.
D="$(newdir)"; build_fw "$D/fw"; build_proj_current "$D/proj" "$FW" "$PIN"
git -C "$FW" rm -q "scripts/validate.sh" >/dev/null 2>&1; rm -f "$FW/scripts/validate.sh"
git -C "$FW" commit -qm "delete validate" >/dev/null 2>&1
rm -f "$D/proj/scripts/validate.sh"                # gone from BOTH sides
run "$D/proj"
mach="$(printf '%s' "$OUT" | sed -n '/```soif-freshness/,/```/p' | sed '1d;$d')"
gverb="$(printf '%s' "$mach" | jq -r '.items[] | select(.id=="missing:scripts/validate.sh") | .verb' 2>/dev/null)"
norph="$(printf '%s' "$mach" | jq -r '[.items[] | select(.id=="orphan:scripts/validate.sh")] | length' 2>/dev/null)"
if [ "$gverb" = "untrack" ] && [ "$norph" = "0" ]; then
  pass "a tracked file gone from BOTH sides is a stale manifest entry (verb=untrack) — not a retire of a file that is already gone"
else
  fail_ "missing both sides" "verb=[$gverb] orphan-rows=[$norph] out=[$OUT]"
fi

# ════════════════════════════════════════════════════════════════════════════
echo "=== hook drift (stale managed block) → enforcement ==="
D="$(newdir)"; build_fw "$D/fw"; build_proj_current "$D/proj" "$FW" "$PIN"
# Corrupt the installed commit-msg managed block so it differs from the template.
sed -i.bak 's/scripts\/pre-commit-gate.sh --terminal-mode --tdd-only/echo STALE/' "$D/proj/.git/hooks/commit-msg" && rm -f "$D/proj/.git/hooks/commit-msg.bak"
run "$D/proj"
mach="$(printf '%s' "$OUT" | sed -n '/```soif-freshness/,/```/p' | sed '1d;$d')"
htier="$(printf '%s' "$mach" | jq -r '.items[] | select(.id=="hook-drift:commit-msg") | .tier' 2>/dev/null)"
[ "$htier" = "enforcement" ] && pass "stale hook managed block is ENFORCEMENT tier" \
  || fail_ "hook-drift" "tier=[$htier] out=[$OUT]"

# ════════════════════════════════════════════════════════════════════════════
echo "=== hook missing when expected present → enforcement ==="
D="$(newdir)"; build_fw "$D/fw"; build_proj_current "$D/proj" "$FW" "$PIN"
rm -f "$D/proj/.git/hooks/commit-msg"
run "$D/proj"
mach="$(printf '%s' "$OUT" | sed -n '/```soif-freshness/,/```/p' | sed '1d;$d')"
htier="$(printf '%s' "$mach" | jq -r '.items[] | select(.id=="hook-missing:commit-msg") | .tier' 2>/dev/null)"
[ "$htier" = "enforcement" ] && pass "missing expected hook is ENFORCEMENT tier" \
  || fail_ "hook-missing" "tier=[$htier] out=[$OUT]"

# ════════════════════════════════════════════════════════════════════════════
echo "=== hook absent-unavailable → enforcement (BL-107) ==="
D="$(newdir)"; build_fw "$D/fw"; build_proj_current "$D/proj" "$FW" "$PIN"
jq '.currency.hooks["commit-msg"]="absent-unavailable"' "$D/proj/.claude/manifest.json" > "$D/proj/.claude/m.tmp" && mv "$D/proj/.claude/m.tmp" "$D/proj/.claude/manifest.json"
rm -f "$D/proj/.git/hooks/commit-msg"
run "$D/proj"
mach="$(printf '%s' "$OUT" | sed -n '/```soif-freshness/,/```/p' | sed '1d;$d')"
utier="$(printf '%s' "$mach" | jq -r '.items[] | select(.id=="hook-unavailable:commit-msg") | .tier' 2>/dev/null)"
if [ "$utier" = "enforcement" ] && printf '%s' "$OUT" | grep -q 'BL-107'; then
  pass "absent-unavailable hook is ENFORCEMENT tier and cites BL-107"
else
  fail_ "hook-unavailable" "tier=[$utier] out=[$OUT]"
fi

# ════════════════════════════════════════════════════════════════════════════
echo "=== hook absent-intentional → silent ==="
D="$(newdir)"; build_fw "$D/fw"; build_proj_current "$D/proj" "$FW" "$PIN"
jq '.currency.hooks["commit-msg"]="absent-intentional"' "$D/proj/.claude/manifest.json" > "$D/proj/.claude/m.tmp" && mv "$D/proj/.claude/m.tmp" "$D/proj/.claude/manifest.json"
rm -f "$D/proj/.git/hooks/commit-msg"
run "$D/proj"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  pass "absent-intentional hook is silent (a real expected absence)"
else
  fail_ "hook-absent-intentional" "rc=$RC out=[$OUT]"
fi

# ════════════════════════════════════════════════════════════════════════════
echo "=== render-base drift → informational ==="
D="$(newdir)"; build_fw "$D/fw"; build_proj_current "$D/proj" "$FW" "$PIN"
printf 'CLAUDE template v2 (changed)\n' > "$FW/templates/generated/claude-md.tmpl"
run "$D/proj"
mach="$(printf '%s' "$OUT" | sed -n '/```soif-freshness/,/```/p' | sed '1d;$d')"
rtier="$(printf '%s' "$mach" | jq -r '.items[] | select(.id=="render-base:CLAUDE.md") | .tier' 2>/dev/null)"
if [ "$rtier" = "informational" ] && printf '%s' "$OUT" | grep -qi 'older template'; then
  pass "render-base drift is informational ('older template')"
else
  fail_ "render-base" "tier=[$rtier] out=[$OUT]"
fi

# ════════════════════════════════════════════════════════════════════════════
echo "=== pin-absent → framework checks skip SILENTLY (BL-110 interim) ==="
D="$(newdir)"; build_fw "$D/fw"; build_proj_current "$D/proj" "$FW" "$PIN"
# Real upstream drift exists, but with no pin the framework check must stay silent.
printf 'echo gate v2 upstream\n' > "$FW/scripts/pre-commit-gate.sh"; git -C "$FW" add -A >/dev/null 2>&1; git -C "$FW" commit -qm bump >/dev/null 2>&1
jq 'del(.soloFrameworkCommit)' "$D/proj/.claude/manifest.json" > "$D/proj/.claude/m.tmp" && mv "$D/proj/.claude/m.tmp" "$D/proj/.claude/manifest.json"
run "$D/proj"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  pass "pin-absent manifest → framework-drift check skips silently"
else
  fail_ "pin-absent-skip" "rc=$RC out=[$OUT]"
fi

# ════════════════════════════════════════════════════════════════════════════
echo "=== path-missing → framework checks skip SILENTLY ==="
D="$(newdir)"; build_fw "$D/fw"; build_proj_current "$D/proj" "$FW" "$PIN"
jq --arg p "$TOP/does-not-exist" '.currency.soloFrameworkPath=$p' "$D/proj/.claude/manifest.json" > "$D/proj/.claude/m.tmp" && mv "$D/proj/.claude/m.tmp" "$D/proj/.claude/manifest.json"
run "$D/proj"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  pass "missing soloFrameworkPath → framework check skips silently"
else
  fail_ "path-missing-skip" "rc=$RC out=[$OUT]"
fi

# ════════════════════════════════════════════════════════════════════════════
echo "=== CDF staleness → informational; CDF absent → silent ==="
D="$(newdir)"; build_fw "$D/fw"; build_proj_current "$D/proj" "$FW" "$PIN"
CDFD="$D/cdf"; mkdir -p "$CDFD"; git -C "$CDFD" init -q; git -C "$CDFD" config user.email t@t.t; git -C "$CDFD" config user.name t
printf 'a\n' > "$CDFD/f"; git -C "$CDFD" add -A; git -C "$CDFD" commit -qm c1
CDFPIN="$(git -C "$CDFD" rev-parse HEAD)"
printf 'b\n' > "$CDFD/f"; git -C "$CDFD" add -A; git -C "$CDFD" commit -qm c2
jq --arg p "$CDFPIN" '.frameworkCommit=$p' "$D/proj/.claude/manifest.json" > "$D/proj/.claude/m.tmp" && mv "$D/proj/.claude/m.tmp" "$D/proj/.claude/manifest.json"
CDF_HOME="$CDFD" run "$D/proj"
mach="$(printf '%s' "$OUT" | sed -n '/```soif-freshness/,/```/p' | sed '1d;$d')"
ctier="$(printf '%s' "$mach" | jq -r '.items[] | select(.id=="cdf-behind") | .tier' 2>/dev/null)"
[ "$ctier" = "informational" ] && pass "CDF staleness is informational" \
  || fail_ "cdf-stale" "tier=[$ctier] out=[$OUT]"
# CDF absent → the cdf check is silent (this project is otherwise current)
run "$D/proj"   # default CDF_HOME = nonexistent
if [ -z "$OUT" ]; then pass "absent CDF clone → cdf check silent"; else fail_ "cdf-absent" "out=[$OUT]"; fi

# ════════════════════════════════════════════════════════════════════════════
echo "=== torn cache → cold start, never fatal ==="
D="$(newdir)"; build_fw "$D/fw"; build_proj_current "$D/proj" "$FW" "$PIN"
mkdir -p "$D/proj/.claude/cache"; printf '{ this is not valid json ::: ' > "$D/proj/.claude/cache/freshness.json"
run "$D/proj"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ] && jq -e . "$D/proj/.claude/cache/freshness.json" >/dev/null 2>&1; then
  pass "torn cache is treated as cold (exit 0, silent, cache rewritten valid)"
else
  fail_ "torn-cache" "rc=$RC out=[$OUT]"
fi

# ── Snooze fixtures use the enforcement 'hook-unavailable' item (stable sig) ──
# seed_snooze <proj> <id> <tier> <snoozedAt> <sig>
seed_snooze() {
  local proj="$1" id="$2" tier="$3" at="$4" sig="$5"
  mkdir -p "$proj/.claude/cache"
  jq -n --arg id "$id" --arg tier "$tier" --argjson at "$at" --arg sig "$sig" \
    '{schemaVersion:1, updatedAt:$at, snoozes:{ ($id): {tier:$tier, snoozedAt:$at, deltaSig:$sig} }}' \
    > "$proj/.claude/cache/freshness.json"
}
# an enforcement-only project (absent-unavailable commit-msg, otherwise current)
mk_enf_proj() {
  local proj="$1" fw="$2" pin="$3"
  build_proj_current "$proj" "$fw" "$pin"
  jq '.currency.hooks["commit-msg"]="absent-unavailable"' "$proj/.claude/manifest.json" > "$proj/.claude/m.tmp" && mv "$proj/.claude/m.tmp" "$proj/.claude/manifest.json"
  rm -f "$proj/.git/hooks/commit-msg"
}
NOW=1800000000
DAY=86400

echo "=== snooze 6-day (enforcement) → held: item suppressed, standing line ==="
D="$(newdir)"; build_fw "$D/fw"; mk_enf_proj "$D/proj" "$FW" "$PIN"
seed_snooze "$D/proj" "hook-unavailable:commit-msg" enforcement "$((NOW - 6*DAY))" "unavailable"
SOIF_FRESHNESS_NOW="$NOW" run "$D/proj"
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'enforcement items snoozed' \
   && ! printf '%s' "$OUT" | grep -q 'BL-107'; then
  pass "6-day enforcement snooze is HELD (item suppressed, standing line printed)"
else
  fail_ "snooze-6day-held" "out=[$OUT]"
fi

echo "=== snooze 8-day (enforcement) → EXPIRED: item re-surfaces ==="
D="$(newdir)"; build_fw "$D/fw"; mk_enf_proj "$D/proj" "$FW" "$PIN"
seed_snooze "$D/proj" "hook-unavailable:commit-msg" enforcement "$((NOW - 8*DAY))" "unavailable"
SOIF_FRESHNESS_NOW="$NOW" run "$D/proj"
if printf '%s' "$OUT" | grep -q 'BL-107' && printf '%s' "$OUT" | grep -q 'Recommended now'; then
  pass "8-day enforcement snooze is EXPIRED (item re-surfaces at enforcement tier)"
else
  fail_ "snooze-8day-expired" "out=[$OUT]"
fi

echo "=== snooze FUTURE snoozedAt → clamped to expired: item re-surfaces ==="
D="$(newdir)"; build_fw "$D/fw"; mk_enf_proj "$D/proj" "$FW" "$PIN"
seed_snooze "$D/proj" "hook-unavailable:commit-msg" enforcement "$((NOW + 5*DAY))" "unavailable"
SOIF_FRESHNESS_NOW="$NOW" run "$D/proj"
if printf '%s' "$OUT" | grep -q 'BL-107'; then
  pass "future snoozedAt is clamped to expired (item re-surfaces)"
else
  fail_ "snooze-future-clamp" "out=[$OUT]"
fi

echo "=== informational snooze holds while delta unchanged; voids on delta change ==="
D="$(newdir)"; build_fw "$D/fw"; build_proj_current "$D/proj" "$FW" "$PIN"
printf 'echo edited once\n' > "$D/proj/scripts/validate.sh"
EDIT_SHA="$(sha "$D/proj/scripts/validate.sh")"
seed_snooze "$D/proj" "local-edit:scripts/validate.sh" informational "$((NOW - 30*DAY))" "$EDIT_SHA"
SOIF_FRESHNESS_NOW="$NOW" run "$D/proj"
held_ok=0
[ -z "$OUT" ] && held_ok=1     # only item is snoozed + informational → fully silent
# now change the file again → delta moves → snooze voids → item re-surfaces
printf 'echo edited twice (delta moved)\n' > "$D/proj/scripts/validate.sh"
SOIF_FRESHNESS_NOW="$NOW" run "$D/proj"
if [ "$held_ok" -eq 1 ] && printf '%s' "$OUT" | grep -qi 'archive-and-replace'; then
  pass "informational snooze holds on stable delta, voids when the upstream/local delta changes"
else
  fail_ "info-snooze-delta" "held_ok=$held_ok out=[$OUT]"
fi

# ════════════════════════════════════════════════════════════════════════════
echo "=== machine-block: valid JSON + stable key set ==="
D="$(newdir)"; build_fw "$D/fw"; build_proj_current "$D/proj" "$FW" "$PIN"
printf 'echo drift\n' > "$D/proj/scripts/validate.sh"
run "$D/proj"
mach="$(printf '%s' "$OUT" | sed -n '/```soif-freshness/,/```/p' | sed '1d;$d')"
if printf '%s' "$mach" | jq -e . >/dev/null 2>&1; then
  keys="$(printf '%s' "$mach" | jq -r 'keys | join(",")')"
  want="current,enforcementSnoozed,generatedAt,items,network,schema,toolsCovered"
  schema="$(printf '%s' "$mach" | jq -r '.schema')"
  tools="$(printf '%s' "$mach" | jq -r '.toolsCovered')"
  net="$(printf '%s' "$mach" | jq -r '.network')"
  ikeys="$(printf '%s' "$mach" | jq -r '.items[0] | keys | join(",")')"
  if [ "$keys" = "$want" ] && [ "$schema" = "soif-freshness/1" ] && [ "$tools" = "false" ] && [ "$net" = "none" ] \
     && [ "$ikeys" = "check,id,message,path,tier,verb" ]; then
    pass "machine block is valid JSON with the stable documented key set (tools not covered; network none)"
  else
    fail_ "machine-keys" "keys=[$keys] schema=[$schema] tools=[$tools] net=[$net] ikeys=[$ikeys]"
  fi
else
  fail_ "machine-json" "not valid JSON: [$mach]"
fi

# ════════════════════════════════════════════════════════════════════════════
echo "=== fail-open: injected crash → exit 0 + single unavailable line ==="
D="$(newdir)"; build_fw "$D/fw"; build_proj_current "$D/proj" "$FW" "$PIN"
OUT="$(SOIF_FRESHNESS_SELFTEST_CRASH=1 CDF_HOME="$TOP/no-cdf" CLAUDE_PROJECT_DIR="$D/proj" bash "$SUT" 2>/dev/null)"; RC=$?
if [ "$RC" -eq 0 ] && [ "$OUT" = "[freshness check unavailable]" ]; then
  pass "injected crash → exit 0 + exactly '[freshness check unavailable]'"
else
  fail_ "fail-open-crash" "rc=$RC out=[$OUT]"
fi

# ════════════════════════════════════════════════════════════════════════════
echo "=== --snooze records an ENFORCEMENT snooze through bypass-audit.sh (M5) ==="
D="$(newdir)"; build_fw "$D/fw"; mk_enf_proj "$D/proj" "$FW" "$PIN"
SOIF_FRESHNESS_NOW="$NOW" CDF_HOME="$TOP/no-cdf" CLAUDE_PROJECT_DIR="$D/proj" bash "$SUT" --snooze "hook-unavailable:commit-msg" >/dev/null 2>&1
snz="$(jq -r '.snoozes["hook-unavailable:commit-msg"].tier // empty' "$D/proj/.claude/cache/freshness.json" 2>/dev/null)"
audit_rows="$(jq '[.[] | select(.type=="freshness_enforcement_snooze")] | length' "$D/proj/.claude/bypass-audit.json" 2>/dev/null || echo 0)"
if [ "$snz" = "enforcement" ] && [ "${audit_rows:-0}" -ge 1 ]; then
  pass "--snooze writes the cache snooze AND records a bypass-audit row (M5)"
else
  fail_ "snooze-audit" "cache-tier=[$snz] audit_rows=[$audit_rows]"
fi
# and the freshly-snoozed enforcement item is now suppressed + standing line
SOIF_FRESHNESS_NOW="$NOW" run "$D/proj"
if printf '%s' "$OUT" | grep -q 'enforcement items snoozed' && ! printf '%s' "$OUT" | grep -q 'BL-107'; then
  pass "after --snooze the enforcement item is suppressed (standing line only)"
else
  fail_ "post-snooze-suppressed" "out=[$OUT]"
fi

# ── Tally ────────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

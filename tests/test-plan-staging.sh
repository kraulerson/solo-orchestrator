#!/usr/bin/env bash
# tests/test-plan-staging.sh — BL-109 S3 UNIT lane for the --plan staging engine
# (scripts/lib/plan-staging.sh). Hermetic: builds scratch FRAMEWORK git repos +
# fixture project manifests (NO init.sh — that is the aggregator, test-plan-birth.sh).
# Zero network. bash-3.2 safe.
#
# Covers: run-folder shape; EXCLUSIVE mkdir collision; verbs (update/add/retire +
# rename linkage); the pinned checkbox grammar; base-sha recording; the shallow-
# clone roll-up fallback line; pin-absent degradation; A2 structural-only (no
# merge/patch, ever); A1 candidate placeholder-free + withheld-on-stray-placeholder;
# the A1 three-way LEG ORDER; the I11 consent scope (hooks + gate scripts) and the
# I1 run-folder write fence (plus a sensitivity test proving the fence is not blind);
# and the # BL-109-PLAN dispatch (via the real upgrade-project.sh). Several tests
# double as the killing tests driven by tests/test-bl099-guard-coverage.sh (PLAN_ONLY
# selects one; PLAN_REPO_OVERRIDE re-points the sourced libs + upgrade-project.sh at a
# mutant tree).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# LIB_ROOT: the tree the libs + upgrade-project.sh are sourced/run FROM. The guard-
# coverage harness sets PLAN_REPO_OVERRIDE to a mutant tree to prove a neuter RED.
LIB_ROOT="${PLAN_REPO_OVERRIDE:-$REPO_ROOT}"
ONLY="${PLAN_ONLY:-}"

unset GITHUB_BASE_REF 2>/dev/null || true

# shellcheck source=/dev/null
. "$LIB_ROOT/scripts/lib/hook-templates.sh"
# shellcheck source=/dev/null
. "$LIB_ROOT/scripts/lib/scaffold-shipped-set.sh"
# shellcheck source=/dev/null
. "$LIB_ROOT/scripts/lib/currency-manifest.sh"
# shellcheck source=/dev/null
. "$LIB_ROOT/scripts/lib/freshness-detect.sh"
# shellcheck source=/dev/null
. "$LIB_ROOT/scripts/lib/render-project-docs.sh"
# shellcheck source=/dev/null
. "$LIB_ROOT/scripts/lib/plan-staging.sh"

PASSED=0; FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  echo "SKIP: jq + git required"; echo "Results: 0 passed, 0 failed"; exit 0
fi

_sha() { shasum -a 256 "$1" | awk '{print $1}'; }
_shastr() { printf '%s' "$1" | shasum -a 256 | awk '{print $1}'; }

# ── Fixture builder ──────────────────────────────────────────────────────────
# mk_fixture <basedir> <pin_mode:real|absent|bogus> <stray:0|1>
#   Sets globals FW, PROJ, PIN. Builds a scratch framework git repo (drift/add/
#   orphan/rename/A1/A2 all present) + a project with a currency manifest.
FW=""; PROJ=""; PIN=""
mk_fixture() {
  local base="$1" pin_mode="$2" stray="${3:-0}"
  FW="$base/fw"; PROJ="$base/proj"
  mkdir -p "$FW/scripts/lib" "$FW/docs" "$FW/templates/generated" "$FW/scripts/hooks"
  cat > "$FW/init.sh" <<'EOF'
#!/usr/bin/env bash
cp "$SCRIPT_DIR/scripts/foo.sh" scripts/
cp "$SCRIPT_DIR/scripts/pre-commit-gate.sh" scripts/
cp "$SCRIPT_DIR/scripts/newname.sh" scripts/
cp "$SCRIPT_DIR/docs/builders-guide.md" docs/reference/
cp "$SCRIPT_DIR/templates/generated/adr.tmpl" templates/generated/
cp "$SCRIPT_DIR/templates/generated/claude-md.tmpl" templates/generated/
cp "$SCRIPT_DIR/templates/generated/project-bible.tmpl" templates/generated/
EOF
  printf 'echo foo v2\n'  > "$FW/scripts/foo.sh"
  printf 'echo gate v2\n' > "$FW/scripts/pre-commit-gate.sh"
  printf 'renamed-content\n' > "$FW/scripts/newname.sh"
  printf '# Builders Guide v2\n' > "$FW/docs/builders-guide.md"
  printf '# ADR template v2\n'   > "$FW/templates/generated/adr.tmpl"
  cp "$LIB_ROOT/scripts/lib/hook-templates.sh" "$FW/scripts/lib/hook-templates.sh"
  # A tiny, CONTROLLABLE intake template (the real 600-line one is unnecessary here):
  # only __DATE__ is a generator placeholder; the pre-fill sed's table-row patterns
  # simply no-op against it. OLD at the pin.
  printf '# Intake\n| **Date** | __DATE__ |\nintake body pin\n' > "$FW/templates/project-intake.md"
  # claude-md template — OLD at the pin
  local strayline=""
  [ "$stray" = "1" ] && strayline="stray __STRAYVAR__ token\n"
  printf "# CLAUDE.md — __PROJECT_NAME__\n- **Project:** __PROJECT_NAME__\n- **Description:** __PROJECT_DESCRIPTION__\n${strayline}old body line\n" > "$FW/templates/generated/claude-md.tmpl"
  # project-bible template — OLD at the pin (2 sections)
  printf '# Project Bible\n\n## Section A\nalpha\n\n## Section B\nbeta\n' > "$FW/templates/generated/project-bible.tmpl"
  ( cd "$FW" && git init -q && git config user.email t@t.local && git config user.name t \
      && git add -A && git commit -qm c0 ) >/dev/null 2>&1
  PIN="$(git -C "$FW" rev-parse HEAD)"
  # advance framework to HEAD: change claude-md (NEW body), intake (NEW body),
  # project-bible (add Section C).
  printf "# CLAUDE.md — __PROJECT_NAME__\n- **Project:** __PROJECT_NAME__\n- **Description:** __PROJECT_DESCRIPTION__\n${strayline}NEW upstream body line\nextra new line\n" > "$FW/templates/generated/claude-md.tmpl"
  printf '# Intake\n| **Date** | __DATE__ |\nintake body NEW upstream line\n' > "$FW/templates/project-intake.md"
  printf '# Project Bible\n\n## Section A\nalpha\n\n## Section B\nbeta\n\n## Section C\ngamma upstream\n' > "$FW/templates/generated/project-bible.tmpl"
  ( cd "$FW" && git add -A && git commit -qm c1 ) >/dev/null 2>&1

  # ── project ──
  mkdir -p "$PROJ/.claude" "$PROJ/scripts" "$PROJ/docs/reference" "$PROJ/templates/generated"
  printf 'echo foo v1\n'  > "$PROJ/scripts/foo.sh"
  printf 'echo gate v1\n' > "$PROJ/scripts/pre-commit-gate.sh"
  printf '# Builders Guide v1\n' > "$PROJ/docs/reference/builders-guide.md"
  printf 'renamed-content\n' > "$PROJ/scripts/oldname.sh"   # rename source (sha == fw newname)
  printf 'dead\n'           > "$PROJ/scripts/deadfile.sh"    # pure retire
  printf '# CLAUDE.md — smoke-proj\n- **Project:** smoke-proj\n- **Description:** a smoke test\nold body line\n' > "$PROJ/CLAUDE.md"
  # rendered-old intake + a user tooling append (ours-only trailing content the
  # three-way must preserve — plan cannot recover the resolver output, review-r1 B3b).
  printf '# Intake\n| **Date** | 2026-07-01 |\nintake body pin\n\n---\n\n## Tooling Configuration\nmy resolved tools\n' > "$PROJ/PROJECT_INTAKE.md"
  printf '# Project Bible\n\n## Section A\nmy alpha prose\n' > "$PROJ/PROJECT_BIBLE.md"
  cat > "$PROJ/.claude/phase-state.json" <<EOF
{"project":"smoke-proj","track":"standard","deployment":"personal","current_phase":0}
EOF
  cat > "$PROJ/.claude/tool-preferences.json" <<EOF
{"resolved_at":"2026-07-01","context":{"platform":"web","language":"typescript","track":"standard"}}
EOF
  local pinjson=""
  case "$pin_mode" in
    real)   pinjson="\"soloFrameworkCommit\": \"$PIN\"," ;;
    bogus)  pinjson="\"soloFrameworkCommit\": \"0000000000000000000000000000000000000000\"," ;;
    absent) pinjson="" ;;
  esac
  local sha_oldtpl sha_oldbible sha_oldintake
  sha_oldtpl="$(git -C "$FW" show "$PIN:templates/generated/claude-md.tmpl" | shasum -a 256 | awk '{print $1}')"
  sha_oldbible="$(git -C "$FW" show "$PIN:templates/generated/project-bible.tmpl" | shasum -a 256 | awk '{print $1}')"
  sha_oldintake="$(git -C "$FW" show "$PIN:templates/project-intake.md" | shasum -a 256 | awk '{print $1}')"
  cat > "$PROJ/.claude/manifest.json" <<EOF
{
  $pinjson
  "currency": {
    "schemaVersion": 1,
    "soloFrameworkPath": "$FW",
    "files": {
      "scripts/foo.sh": {"sha256":"$(_sha "$PROJ/scripts/foo.sh")","mode":"755","class":"M","state":"current"},
      "scripts/pre-commit-gate.sh": {"sha256":"$(_sha "$PROJ/scripts/pre-commit-gate.sh")","mode":"755","class":"M","state":"current"},
      "scripts/oldname.sh": {"sha256":"$(_sha "$PROJ/scripts/oldname.sh")","mode":"755","class":"M","state":"current"},
      "scripts/deadfile.sh": {"sha256":"$(_sha "$PROJ/scripts/deadfile.sh")","mode":"755","class":"M","state":"current"},
      "docs/reference/builders-guide.md": {"sha256":"$(_sha "$PROJ/docs/reference/builders-guide.md")","mode":"644","class":"T","state":"current"}
    },
    "renderBases": {
      "A1": {
        "CLAUDE.md": {"templateSha":"$sha_oldtpl","outputSha":"$(_sha "$PROJ/CLAUDE.md")"},
        "PROJECT_INTAKE.md": {"templateSha":"$sha_oldintake","outputSha":"$(_sha "$PROJ/PROJECT_INTAKE.md")"}
      },
      "A2": {"PROJECT_BIBLE.md": {"templateSha":"$sha_oldbible"}}
    },
    "hooks": {}, "mcpProbe": {"context7":"absent"}
  }
}
EOF
}

# _fingerprint <root> [run_folder_to_exclude] — sha of EVERY file under <root>, minus
# ONLY the one run folder this invocation created.
#
# S3 review round 1 (MINOR-2): this used to exclude the whole `*/docs/updates/*`
# subtree, which made the I1 fence test blind to exactly the writes it exists to
# catch — a stray write to docs/updates/STRAY.txt is INSIDE the container dir but
# OUTSIDE the dated run folder, and the fence never saw it. The run-id is known to the
# caller, so exclude precisely that folder and nothing else: any other write anywhere
# in the tree — including elsewhere under docs/updates/ — now trips the fence.
# Pinned by t_i1_fence_catches_stray_outside_run_folder.
_fingerprint() {
  local root="$1" excl="${2:-}"
  find "$root" -type f 2>/dev/null | sort | while IFS= read -r f; do
    if [ -n "$excl" ]; then
      case "$f" in "$excl"/*) continue ;; esac
    fi
    printf '%s  %s\n' "$(_sha "$f")" "${f#"$root"}"
  done
}

# mk_drifted_hook — install a commit-msg hook whose managed block is STALE vs the
# framework template, and declare it in the manifest, so the detector emits a hook item.
mk_drifted_hook() {
  mkdir -p "$PROJ/.git/hooks"
  printf '#!/bin/sh\n%s\nstale body\n%s\n' "$SOIF_TDD_OPEN" "$SOIF_TDD_CLOSE" > "$PROJ/.git/hooks/commit-msg"
  jq '.currency.hooks = {"commit-msg":"present"}' "$PROJ/.claude/manifest.json" > "$PROJ/.claude/m.tmp" \
    && mv "$PROJ/.claude/m.tmp" "$PROJ/.claude/manifest.json"
}

# ── The I11 (class × verb) CROSS-PRODUCT fixture (# BL-109-I11-PAYLOAD) ──────────
# mk_i11_matrix <basedir> [empty_gate:0|1]
#
# ONE plan run that produces EVERY I11 (class × verb) combination the engine can emit,
# plus non-I11 controls. The point is not to test four verbs that happen to work today:
# it is that a future verb whose diff arm is missing lands in this matrix automatically,
# and the payload guard turns it into a hard, named failure instead of a blank code block
# under a heading promising a full diff.
#
#   class=M  gate  verb=update  scripts/pre-commit-gate.sh       v1 → v2
#   class=M  gate  verb=add     scripts/run-phase3-validation.sh upstream-only
#   class=M  gate  verb=retire  scripts/process-checklist.sh     downstream-only, no sha match
#   class=M  gate  verb=rename  scripts/check-gate.sh ↔ scripts/check-phase-gate.sh (sha match)
#                               → TWO linked rows, BOTH I11, each rendering its own side
#   class=hook     verb=update  commit-msg  (installed managed block is stale)
#   class=hook     verb=add     pre-commit  (managed block missing from the installed hook)
#
#   CONTROLS (must NOT be I11, must NOT be enforcement tier):
#   class=M  ord   verb=update  scripts/foo.sh
#   class=M  ord   verb=retire  scripts/deadfile.sh   ← the # BL-109-PLAN-TIER case
#
# empty_gate=1 makes the upstream source of the gate-script ADD a ZERO-BYTE file, which
# is the one way a real plan run can reach the emission site with a legitimately empty
# I11 payload — the forcing function for the hard-error test.
mk_i11_matrix() {
  local base="$1" empty_gate="${2:-0}"
  FW="$base/fw"; PROJ="$base/proj"
  mkdir -p "$FW/scripts/lib" "$PROJ/.claude" "$PROJ/scripts" "$PROJ/.git/hooks"
  cat > "$FW/init.sh" <<'EOF'
#!/usr/bin/env bash
cp "$SCRIPT_DIR/scripts/foo.sh" scripts/
cp "$SCRIPT_DIR/scripts/pre-commit-gate.sh" scripts/
cp "$SCRIPT_DIR/scripts/check-phase-gate.sh" scripts/
cp "$SCRIPT_DIR/scripts/run-phase3-validation.sh" scripts/
EOF
  printf 'echo foo v2\n'          > "$FW/scripts/foo.sh"
  printf 'echo gate v2\n'         > "$FW/scripts/pre-commit-gate.sh"
  printf 'moved-gate-body\n'      > "$FW/scripts/check-phase-gate.sh"   # rename TARGET
  if [ "$empty_gate" = "1" ]; then
    : > "$FW/scripts/run-phase3-validation.sh"                          # 0 bytes → empty payload
  else
    printf 'echo phase3 v1\n'     > "$FW/scripts/run-phase3-validation.sh"
  fi
  cp "$LIB_ROOT/scripts/lib/hook-templates.sh" "$FW/scripts/lib/hook-templates.sh"
  ( cd "$FW" && git init -q && git config user.email t@t.local && git config user.name t \
      && git add -A && git commit -qm c0 ) >/dev/null 2>&1
  PIN="$(git -C "$FW" rev-parse HEAD)"

  printf 'echo foo v1\n'          > "$PROJ/scripts/foo.sh"              # ordinary update (control)
  printf 'echo gate v1\n'         > "$PROJ/scripts/pre-commit-gate.sh"  # gate update
  printf 'moved-gate-body\n'      > "$PROJ/scripts/check-gate.sh"       # rename SOURCE (sha match)
  printf 'checklist body\n'       > "$PROJ/scripts/process-checklist.sh" # gate retire (no match)
  printf 'dead\n'                 > "$PROJ/scripts/deadfile.sh"         # ordinary retire (control)
  # hook UPDATE — stale managed block; hook ADD — an installed hook with NO managed block.
  printf '#!/bin/sh\n%s\nstale body\n%s\n' "$SOIF_TDD_OPEN" "$SOIF_TDD_CLOSE" > "$PROJ/.git/hooks/commit-msg"
  printf '#!/bin/sh\necho my own pre-commit\n' > "$PROJ/.git/hooks/pre-commit"

  cat > "$PROJ/.claude/manifest.json" <<EOF
{
  "soloFrameworkCommit": "$PIN",
  "currency": {
    "schemaVersion": 1,
    "soloFrameworkPath": "$FW",
    "files": {
      "scripts/foo.sh": {"sha256":"$(_sha "$PROJ/scripts/foo.sh")","mode":"755","class":"M","state":"current"},
      "scripts/pre-commit-gate.sh": {"sha256":"$(_sha "$PROJ/scripts/pre-commit-gate.sh")","mode":"755","class":"M","state":"current"},
      "scripts/check-gate.sh": {"sha256":"$(_sha "$PROJ/scripts/check-gate.sh")","mode":"755","class":"M","state":"current"},
      "scripts/process-checklist.sh": {"sha256":"$(_sha "$PROJ/scripts/process-checklist.sh")","mode":"755","class":"M","state":"current"},
      "scripts/deadfile.sh": {"sha256":"$(_sha "$PROJ/scripts/deadfile.sh")","mode":"755","class":"M","state":"current"}
    },
    "renderBases": {"A1": {}, "A2": {}},
    "hooks": {"commit-msg": "present", "pre-commit": "present"},
    "mcpProbe": {"context7": "absent"}
  }
}
EOF
}

# _i11_section <update-plan> <item-id> — the I11 consent section for ONE item (from its
# `### \`<id>\`` heading to the next `###`/`##` heading). Used to assert the diff BODY,
# never the heading — asserting the heading is exactly how the hollow hook diff shipped.
_i11_section() {
  awk -v want="### \`$2\`" '
    index($0, want)==1 { f=1; next }
    f && (index($0,"### ")==1 || index($0,"## ")==1) { exit }
    f { print }
  ' "$1"
}

# _has_payload <text-on-stdin-file> — a REAL unified-diff payload: a hunk header AND a
# +/- content line. The test-side mirror of _soif_plan_diff_has_payload (deliberately an
# INDEPENDENT re-implementation: a test that called the guard it is testing would go
# green the moment the guard was neutered, which is the whole failure mode being pinned).
_has_payload() {
  local f="$1"
  # POSITIONAL, not spelling — the round-3 lesson, applied to the ORACLE ITSELF.
  # A unified diff's file headers (--- / +++) only ever appear BEFORE the first @@,
  # so ANY line starting with + or - AFTER a hunk header is payload — including one
  # whose text happens to begin '+++'. The old rule here keyed on spelling
  # (^\+ not followed by +), which is exactly the bug the shipped predicate was
  # fixed for: it REJECTS a legitimate one-line change whose added text starts '+++'.
  # This must stay an INDEPENDENT re-implementation (it must never call the guard it
  # tests, or it would go green the moment that guard is neutered) — but independent
  # means independently CORRECT, not independently wrong in the same way.
  grep -q '^@@' "$f" 2>/dev/null || return 1
  awk '/^@@/ { in_hunk = 1; next } in_hunk && /^[+-]/ { found = 1; exit } END { exit !found }' "$f" 2>/dev/null
}

# _tree_fingerprint <root> — sha of every FILE plus the name of every DIRECTORY under
# <root>. Directories are in the fingerprint on purpose: a file-only fingerprint cannot
# see an EMPTY leftover dir, and "a failed --plan left an empty docs/updates/ behind" is
# exactly the trace this fingerprint exists to catch (# BL-109-PLAN-NOTRACE).
_tree_fingerprint() {
  local root="$1" p
  find "$root" \( -type f -o -type d \) 2>/dev/null | sort | while IFS= read -r p; do
    if [ -d "$p" ]; then printf 'DIR   %s\n' "${p#"$root"}"
    else                 printf '%s  %s\n' "$(_sha "$p")" "${p#"$root"}"; fi
  done
}

# _pp_reject / _pp_accept <label> <file> — the two directions of the payload predicate,
# asserted DIRECTLY against _soif_plan_diff_has_payload (the real function, sourced from
# LIB_ROOT — so the guard-coverage harness's mutant lib is what answers here).
_pp_reject() {
  if _soif_plan_diff_has_payload "$2"; then echo "    ACCEPTED a hollow payload — $1"; return 1; fi
  return 0
}
_pp_accept() {
  if ! _soif_plan_diff_has_payload "$2"; then echo "    REJECTED a REAL diff — $1"; return 1; fi
  return 0
}

# ══════════════════════════════════════════════════════════════════════════════
# TESTS
# ══════════════════════════════════════════════════════════════════════════════

t_folder_shape() {
  local b; b="$(mktemp -d)"; mk_fixture "$b" real
  local run; run="$(soif_plan_run "$PROJ" "$FW" "$FW/init.sh" "$b/nocdf")"
  local ok=1
  for p in UPDATE-PLAN.md manifest.json .gitignore incoming diffs review archive merged patches review/README.md; do
    [ -e "$run/$p" ] || { ok=0; echo "    missing: $p"; }
  done
  grep -qx 'incoming/' "$run/.gitignore" && grep -qx 'archive/' "$run/.gitignore" || { ok=0; echo "    .gitignore missing incoming/ or archive/"; }
  [ "$ok" = 1 ] && pass "run-folder shape (all 9 members + .gitignore for incoming/+archive/)" || fail_ "folder shape" "see above"
  rm -rf "$b"
}

t_exclusive_mkdir() {   # killing test: exclusive-mkdir collision guard
  local b; b="$(mktemp -d)"; mk_fixture "$b" real
  local now=1700000000 r1 rc2=0
  r1="$(soif_plan_run "$PROJ" "$FW" "$FW/init.sh" "$b/nocdf" "$now")" || { fail_ "exclusive mkdir" "first plan failed"; rm -rf "$b"; return; }
  # second call, SAME now (and same $$) → identical run-id → EXCLUSIVE mkdir must abort
  soif_plan_run "$PROJ" "$FW" "$FW/init.sh" "$b/nocdf" "$now" >/dev/null 2>&1 || rc2=$?
  if [ "$rc2" != 0 ]; then pass "exclusive mkdir aborts on run-id collision (rc=$rc2)"; else fail_ "exclusive mkdir" "a colliding run-id did NOT abort (guard neutered?)"; fi
  rm -rf "$b"
}

t_verbs_and_rename() {
  local b; b="$(mktemp -d)"; mk_fixture "$b" real
  local run; run="$(soif_plan_run "$PROJ" "$FW" "$FW/init.sh" "$b/nocdf")"
  local m="$run/manifest.json" ok=1
  # update items
  [ "$(jq -r '.items[] | select(.id=="fw-drift:scripts/foo.sh") | .verb' "$m")" = "update" ] || { ok=0; echo "    foo not update"; }
  # add item
  [ "$(jq -r '.items[] | select(.id=="add:templates/generated/adr.tmpl") | .verb' "$m")" = "add" ] || { ok=0; echo "    adr not add"; }
  # pure retire (deadfile — no matching add)
  [ "$(jq -r '.items[] | select(.id=="orphan:scripts/deadfile.sh") | .verb' "$m")" = "retire" ] || { ok=0; echo "    deadfile not retire"; }
  # rename linkage (oldname ↔ newname)
  [ "$(jq -r '.items[] | select(.id=="orphan:scripts/oldname.sh") | .verb' "$m")" = "rename" ] || { ok=0; echo "    oldname not rename"; }
  [ "$(jq -r '.items[] | select(.id=="orphan:scripts/oldname.sh") | .renameOf' "$m")" = "add:scripts/newname.sh" ] || { ok=0; echo "    oldname renameOf wrong"; }
  [ "$(jq -r '.items[] | select(.id=="add:scripts/newname.sh") | .verb' "$m")" = "rename" ] || { ok=0; echo "    newname not rename"; }
  [ "$ok" = 1 ] && pass "verbs: update + add + retire + linked rename pair" || fail_ "verbs/rename" "see above"
  rm -rf "$b"
}

t_retire_emitted() {   # killing test: retire-verb emission (mutation drops it)
  local b; b="$(mktemp -d)"; mk_fixture "$b" real
  local run; run="$(soif_plan_run "$PROJ" "$FW" "$FW/init.sh" "$b/nocdf")"
  local n; n="$(jq -r '[.items[] | select(.verb=="retire" or .verb=="rename")] | length' "$run/manifest.json")"
  if [ "$n" -ge 1 ]; then pass "retire/rename verb emitted for orphaned files ($n)"; else fail_ "retire emission" "no retire/rename item — orphan handling dropped"; fi
  rm -rf "$b"
}

t_grammar_pin() {
  local b; b="$(mktemp -d)"; mk_fixture "$b" real
  local run; run="$(soif_plan_run "$PROJ" "$FW" "$FW/init.sh" "$b/nocdf")"
  local up="$run/UPDATE-PLAN.md" ok=1
  # every checkbox line matches the EXACT pinned grammar, all UNCHECKED
  local bad
  bad="$(grep -E '^- \[' "$up" | grep -vE '^- \[ \] .+ — .+ \(.+/.+\)$' || true)"
  [ -z "$bad" ] || { ok=0; echo "    off-grammar checkbox line(s): $bad"; }
  grep -qE '^- \[x\]' "$up" && { ok=0; echo "    a box was pre-checked"; }
  # count parity: checkbox lines == manifest item count
  local cbc mic
  cbc="$(grep -cE '^- \[ \] ' "$up")"
  mic="$(jq -r '.items | length' "$run/manifest.json")"
  [ "$cbc" = "$mic" ] || { ok=0; echo "    checkbox count $cbc != manifest items $mic"; }
  [ "$ok" = 1 ] && pass "checkbox grammar pinned (all unchecked; count == items == $mic)" || fail_ "grammar pin" "see above"
  rm -rf "$b"
}

t_base_sha_recorded() {   # killing test: base-sha recording
  local b; b="$(mktemp -d)"; mk_fixture "$b" real
  local run; run="$(soif_plan_run "$PROJ" "$FW" "$FW/init.sh" "$b/nocdf")"
  local m="$run/manifest.json" ok=1
  # every non-add item with a live file must carry a baseSha == that file's sha
  local id path base disksha
  while IFS="$(printf '\t')" read -r id path base; do
    [ -n "$id" ] || continue
    [ -f "$PROJ/$path" ] || continue
    disksha="$(_sha "$PROJ/$path")"
    if [ "$base" != "$disksha" ]; then ok=0; echo "    $id baseSha=$base != disk=$disksha"; fi
  done < <(jq -r '.items[] | select(.verb != "add") | [.id, .path, (.baseSha // "")] | @tsv' "$m")
  # and at least one baseSha is present (non-null) — the guard actually recorded
  local nz; nz="$(jq -r '[.items[] | select(.baseSha != null)] | length' "$m")"
  [ "$nz" -ge 1 ] || { ok=0; echo "    NO item recorded a baseSha at all"; }
  [ "$ok" = 1 ] && pass "base-sha recorded == live file sha for every non-add item ($nz present)" || fail_ "base-sha" "see above"
  rm -rf "$b"
}

t_rollup_shallow_fallback() {
  local b; b="$(mktemp -d)"; mk_fixture "$b" bogus   # pin present but NOT in the clone
  local run; run="$(soif_plan_run "$PROJ" "$FW" "$FW/init.sh" "$b/nocdf")"
  # a bogus (unresolvable) pin → every roll-up is the EXACT shallow-clone fallback line
  if grep -qF 'history unavailable (shallow clone — git fetch --unshallow to enable)' "$run"/diffs/*.diff 2>/dev/null; then
    pass "shallow-clone roll-up fallback line emitted verbatim (unresolvable pin)"
  else
    fail_ "roll-up fallback" "the exact review-r1 M1 fallback line was not found in any diff"
  fi
  rm -rf "$b"
}

t_pin_absent_degrades() {
  local b; b="$(mktemp -d)"; mk_fixture "$b" absent
  local run rc=0; run="$(soif_plan_run "$PROJ" "$FW" "$FW/init.sh" "$b/nocdf")" || rc=$?
  local ok=1
  # S3 review round 1 (MINOR-1): this line WAS `[ "$rc" = 0 ] || { ok=1; }` — the
  # failure branch set the PASS value, so it asserted nothing. Pin-absent is a
  # DEGRADE, not an error: the run must still succeed (rc 0) and produce the folder.
  [ "$rc" = 0 ] || { ok=0; echo "    soif_plan_run returned rc=$rc pin-absent (must degrade, never fail)"; }
  [ -d "$run" ] || { ok=0; echo "    no run folder produced pin-absent"; }
  local m="$run/manifest.json"
  # framework-comparison verbs are UNAVAILABLE pin-absent (no drift/add/retire/rename)
  local fwc; fwc="$(jq -r '[.items[] | select(.verb=="update" and (.class=="M" or .class=="T"))] + [.items[]|select(.verb=="add" or .verb=="retire" or .verb=="rename")] | length' "$m")"
  [ "$fwc" = "0" ] || { ok=0; echo "    framework-comparison items present pin-absent ($fwc)"; }
  # render-base A2 still derivable (does not need the pin)
  jq -e '.items[] | select(.id=="render-base:PROJECT_BIBLE.md")' "$m" >/dev/null 2>&1 || { ok=0; echo "    render-base item lost pin-absent"; }
  # A1 candidate WITHHELD pin-absent (cannot recover the old template)
  [ -e "$run/merged/CLAUDE.md.candidate" ] && { ok=0; echo "    A1 candidate built despite pin-absent"; }
  # UPDATE-PLAN carries the pin-absent notice
  grep -qi 'pin absent' "$run/UPDATE-PLAN.md" || { ok=0; echo "    no pin-absent notice"; }
  [ "$ok" = 1 ] && pass "pin-absent: plan runs, degrades to render-base/hook, notice present, no A1 candidate" || fail_ "pin-absent" "see above"
  rm -rf "$b"
}

t_a2_structural_only() {   # killing test: A2 fence (no merge/patch, ever)
  local b; b="$(mktemp -d)"; mk_fixture "$b" real
  local run; run="$(soif_plan_run "$PROJ" "$FW" "$FW/init.sh" "$b/nocdf")"
  local ok=1
  # structural review file exists
  [ -f "$run/review/PROJECT_BIBLE.md.structural.md" ] || { ok=0; echo "    no A2 structural file"; }
  # NO merged candidate + NO patch for ANY A2 artifact — the fence
  ls "$run"/merged/PROJECT_BIBLE.md* >/dev/null 2>&1 && { ok=0; echo "    A2 candidate leaked into merged/ (fence breached)"; }
  ls "$run"/merged/PRODUCT_MANIFESTO* >/dev/null 2>&1 && { ok=0; echo "    manifesto candidate in merged/"; }
  ls "$run"/patches/PROJECT_BIBLE.md* >/dev/null 2>&1 && { ok=0; echo "    A2 patch leaked into patches/"; }
  [ "$(jq -r '.items[] | select(.class=="A2") | .candidate' "$run/manifest.json")" = "null" ] || { ok=0; echo "    A2 manifest item has a candidate"; }
  # missing sections (B, C) staged as INSERT-BY-HAND skeletons
  ls "$run"/incoming/PROJECT_BIBLE.md.section.* >/dev/null 2>&1 || { ok=0; echo "    no A2 skeletons staged in incoming/"; }
  [ "$ok" = 1 ] && pass "A2 structural-only: review + skeletons, NEVER a merge/patch (fence holds)" || fail_ "A2 fence" "see above"
  rm -rf "$b"
}

t_a1_candidate_placeholder_free() {   # killing test path shares the placeholder guard
  local b; b="$(mktemp -d)"; mk_fixture "$b" real 0
  local run; run="$(soif_plan_run "$PROJ" "$FW" "$FW/init.sh" "$b/nocdf")"
  local ok=1
  [ -f "$run/merged/CLAUDE.md.candidate" ] || { ok=0; echo "    no A1 candidate built"; }
  if [ -f "$run/merged/CLAUDE.md.candidate" ]; then
    grep -qE '__[A-Z][A-Z_]*__' "$run/merged/CLAUDE.md.candidate" && { ok=0; echo "    candidate contains a generator placeholder"; }
    grep -q 'smoke-proj' "$run/merged/CLAUDE.md.candidate" || { ok=0; echo "    candidate lost the recovered project name"; }
    grep -q 'NEW upstream body line' "$run/merged/CLAUDE.md.candidate" || { ok=0; echo "    candidate did not pick up the upstream template change"; }
  fi
  [ "$ok" = 1 ] && pass "A1 candidate is placeholder-free, keeps user values, applies the upstream delta" || fail_ "A1 candidate" "see above"
  rm -rf "$b"
}

t_a1_intake_candidate() {
  local b; b="$(mktemp -d)"; mk_fixture "$b" real 0
  local run; run="$(soif_plan_run "$PROJ" "$FW" "$FW/init.sh" "$b/nocdf")"
  local cand="$run/merged/PROJECT_INTAKE.md.candidate" ok=1
  [ -f "$cand" ] || { ok=0; echo "    no PROJECT_INTAKE.md candidate"; }
  if [ -f "$cand" ]; then
    grep -qE '__[A-Z][A-Z_]*__' "$cand" && { ok=0; echo "    intake candidate has a generator placeholder (e.g. __DATE__)"; }
    grep -q 'intake body NEW upstream line' "$cand" || { ok=0; echo "    intake candidate missed the upstream delta"; }
    grep -q 'Tooling Configuration' "$cand" || { ok=0; echo "    intake candidate dropped the user tooling append (ours-only content lost)"; }
  fi
  [ "$ok" = 1 ] && pass "A1 PROJECT_INTAKE candidate: __DATE__ filled, upstream delta applied, user tooling append preserved" \
    || fail_ "A1 intake candidate" "see above"
  rm -rf "$b"
}

t_a1_placeholder_withheld() {   # killing test: A1 placeholder-free assertion
  local b; b="$(mktemp -d)"; mk_fixture "$b" real 1   # stray __STRAYVAR__ in the templates
  local run; run="$(soif_plan_run "$PROJ" "$FW" "$FW/init.sh" "$b/nocdf")"
  local ok=1
  # a render leg carries an unrendered placeholder → candidate must be WITHHELD
  [ -e "$run/merged/CLAUDE.md.candidate" ] && { ok=0; echo "    candidate built despite a stray placeholder (guard neutered?)"; }
  [ "$(jq -r '.items[] | select(.id=="render-base:CLAUDE.md") | .candidate' "$run/manifest.json")" = "null" ] || { ok=0; echo "    A1 item still has a candidate"; }
  [ "$ok" = 1 ] && pass "A1 placeholder guard WITHHOLDS the candidate when a render leg is not fully rendered" || fail_ "A1 placeholder withhold" "see above"
  rm -rf "$b"
}

t_i1_write_fence() {   # killing test: plan-fence (writes stay under the run folder)
  local b; b="$(mktemp -d)"; mk_fixture "$b" real
  local before after run
  before="$(_fingerprint "$PROJ")"
  run="$(soif_plan_run "$PROJ" "$FW" "$FW/init.sh" "$b/nocdf" 2>/dev/null)"
  # Exclude ONLY the run folder this call created — every other byte in the tree,
  # docs/updates/ included, is fenced.
  after="$(_fingerprint "$PROJ" "$run")"
  if [ "$before" = "$after" ]; then
    pass "I1 fence: --plan wrote NOTHING in the project tree outside its own run folder"
  else
    fail_ "I1 fence" "the project tree changed outside the run folder:"$'\n'"$(diff <(printf '%s' "$before") <(printf '%s' "$after") | head)"
  fi
  rm -rf "$b"
}

t_i1_fence_catches_stray_outside_run_folder() {
  # The fence test is only worth its name if it can SEE a stray write. Plant one
  # inside the container dir but OUTSIDE the dated run folder — the exact blind spot
  # the old whole-subtree exclusion had (S3 review round 1, MINOR-2) — and prove the
  # fingerprint catches it.
  local b; b="$(mktemp -d)"; mk_fixture "$b" real
  local before after run
  before="$(_fingerprint "$PROJ")"
  run="$(soif_plan_run "$PROJ" "$FW" "$FW/init.sh" "$b/nocdf" 2>/dev/null)"
  printf 'an escaped write\n' > "$PROJ/docs/updates/STRAY.txt"     # simulate a breached fence
  after="$(_fingerprint "$PROJ" "$run")"
  if [ "$before" != "$after" ] && printf '%s\n' "$after" | grep -q 'docs/updates/STRAY.txt'; then
    pass "I1 fence is SENSITIVE: a stray write under docs/updates/ (outside the run folder) trips it"
  else
    fail_ "I1 fence sensitivity" "a stray docs/updates/STRAY.txt did NOT trip the fingerprint — the fence is blind"
  fi
  rm -rf "$b"
}

t_hook_item_consent_full_diff() {
  local b; b="$(mktemp -d)"; mk_fixture "$b" real
  mk_drifted_hook          # a drifted commit-msg hook → a hook item (I11)
  local run; run="$(soif_plan_run "$PROJ" "$FW" "$FW/init.sh" "$b/nocdf")"
  local up="$run/UPDATE-PLAN.md" ok=1
  jq -e '.items[] | select(.class=="hook") | select(.consent=="item")' "$run/manifest.json" >/dev/null 2>&1 || { ok=0; echo "    no hook item with item-consent"; }
  grep -qi 'item-consent required' "$up" || { ok=0; echo "    UPDATE-PLAN lacks the item-consent marker"; }
  # S3 review round 1: this used to assert `grep -qi 'full diff'`, which matches the
  # SECTION HEADING ("FULL diff, I11") — so it passed while the embedded ```diff block
  # was EMPTY (the hook name was resolved off path "-", which matches no marker set).
  # Assert the DIFF BODY itself: real hunk lines for the stale managed region.
  grep -q '^--- installed/commit-msg' "$up" || { ok=0; echo "    no hook diff header (empty diff block?)"; }
  grep -q '^@@' "$up"            || { ok=0; echo "    hook diff has no hunk header — the embedded diff is empty"; }
  grep -q '^-stale body' "$up"   || { ok=0; echo "    hook diff does not show the stale managed-block line being replaced"; }
  grep -qF '**Provenance:** framework `' "$up" || { ok=0; echo "    no provenance (upstream short-sha) for the hook item"; }
  [ "$ok" = 1 ] && pass "hooks are item-consent with a REAL full diff + provenance embedded (I11)" || fail_ "hook I11" "see above"
  rm -rf "$b"
}

t_i11_consent_scope_simultaneous_drift() {   # killing test: # BL-109-I11-CONSENT
  # THE I11 SCOPE TEST. A gate script, a hook and an ordinary Class-M script drift
  # SIMULTANEOUSLY. The first two are the scariest writes the updater can offer (the
  # code that decides whether the operator's own gates block) and must get item-level
  # consent + a FULL embedded unified diff + provenance. The third keeps the ordinary
  # batch-consentable / diffstat treatment. Design v1.1 §3 I11.
  local b; b="$(mktemp -d)"; mk_fixture "$b" real
  mk_drifted_hook
  local run; run="$(soif_plan_run "$PROJ" "$FW" "$FW/init.sh" "$b/nocdf")"
  local up="$run/UPDATE-PLAN.md" m="$run/manifest.json" ok=1
  local gate="fw-drift:scripts/pre-commit-gate.sh" hook="hook-drift:commit-msg" ord="fw-drift:scripts/foo.sh"

  # all three items were actually derived (else the test would pass vacuously)
  for want in "$gate" "$hook" "$ord"; do
    jq -e --arg i "$want" '.items[] | select(.id==$i)' "$m" >/dev/null 2>&1 \
      || { ok=0; echo "    fixture did not produce item $want"; }
  done

  # (1) GATE SCRIPT — item consent, never batch
  [ "$(jq -r --arg i "$gate" '.items[] | select(.id==$i) | .consent' "$m")" = "item" ] \
    || { ok=0; echo "    gate script is NOT item-consent (batch-consentable gate = I11 breach)"; }
  # (2) GATE SCRIPT — the ⚠ marker follows its checkbox line
  grep -A1 -F -- "- [ ] $gate — scripts/pre-commit-gate.sh" "$up" | grep -q 'item-consent required' \
    || { ok=0; echo "    gate script checkbox carries no ⚠ item-consent marker"; }
  # (3) GATE SCRIPT — a FULL embedded unified diff (never diffstat-only) + provenance
  local gsec; gsec="$(awk '/^### `fw-drift:scripts\/pre-commit-gate.sh`/{f=1} f&&/^### `hook-drift/{f=0} f' "$up")"
  printf '%s\n' "$gsec" | grep -q '^@@'            || { ok=0; echo "    gate script has NO hunk header — diffstat-only, the I11 breach"; }
  printf '%s\n' "$gsec" | grep -q '^-echo gate v1' || { ok=0; echo "    gate script diff does not show the removed line"; }
  printf '%s\n' "$gsec" | grep -q '^+echo gate v2' || { ok=0; echo "    gate script diff does not show the added line"; }
  printf '%s\n' "$gsec" | grep -qF '**Provenance:** framework `' || { ok=0; echo "    gate script section carries no provenance"; }
  # (4) HOOK — same treatment, same section
  [ "$(jq -r --arg i "$hook" '.items[] | select(.id==$i) | .consent' "$m")" = "item" ] \
    || { ok=0; echo "    hook is NOT item-consent"; }
  grep -q '^### `hook-drift:commit-msg`' "$up" || { ok=0; echo "    hook has no item-consent section"; }
  # (5) ORDINARY CLASS-M — unchanged: batch-consentable, diffstat in the facts table,
  #     NO ⚠ marker, NO full-diff section (over-fencing every M item would drown the
  #     signal that makes the gate-script fence meaningful).
  [ "$(jq -r --arg i "$ord" '.items[] | select(.id==$i) | .consent' "$m")" = "batch" ] \
    || { ok=0; echo "    ordinary M script was escalated to item-consent (fence too broad)"; }
  grep -A1 -F -- "- [ ] $ord — scripts/foo.sh" "$up" | grep -q 'item-consent required' \
    && { ok=0; echo "    ordinary M script carries an ⚠ item-consent marker"; }
  grep -q '^### `fw-drift:scripts/foo.sh`' "$up" \
    && { ok=0; echo "    ordinary M script got a full-diff item-consent section"; }
  grep -qF '| `fw-drift:scripts/foo.sh` | M | update | +1/-1 |' "$up" \
    || { ok=0; echo "    ordinary M script lost its diffstat row in the mechanical facts table"; }
  [ "$ok" = 1 ] && pass "I11 scope: gate script + hook get item-consent & a FULL diff; the ordinary M script keeps batch/diffstat" \
    || fail_ "I11 consent scope" "see above"
  rm -rf "$b"
}

t_a1_merge_leg_order() {   # killing test: # BL-109-A1-MERGE-LEGS
  # THE THREE-WAY LEG ORDER. `git merge-file -p <ours> <base> <theirs>` with
  # ours=user-now, base=render-THEN, theirs=render-NOW. Swapping base and theirs makes
  # the NEW render the common ancestor, so the merge treats the upstream delta as
  # something to REVERT and SILENTLY DROPS IT — no conflict, no warning, the update
  # the operator asked to stage simply is not there.
  #
  # The three legs are made distinguishable: base has "old body line"; theirs has
  # "NEW upstream body line"/"extra new line"; ours has an ours-only "MY LOCAL EDIT".
  # The correct merge OFFERS the upstream delta (whether cleanly or inside a conflict
  # the operator resolves — conflict markers legitimately stay in the candidate). The
  # swapped merge does not contain it AT ALL. That absence is the kill.
  local b; b="$(mktemp -d)"; mk_fixture "$b" real 0
  printf 'MY LOCAL EDIT\n' >> "$PROJ/CLAUDE.md"     # an ours-only leg (CLAUDE.md is a
                                                    # renderBase, not a files{} entry —
                                                    # this is not a local-edit notice)
  local run; run="$(soif_plan_run "$PROJ" "$FW" "$FW/init.sh" "$b/nocdf")"
  local cand="$run/merged/CLAUDE.md.candidate" ok=1
  # the legs really are distinguishable (else the assertions below prove nothing)
  grep -q 'old body line'        "$run/incoming/CLAUDE.md.render.then" || { ok=0; echo "    base leg (render-then) is not the OLD render"; }
  grep -q 'NEW upstream body line' "$run/incoming/CLAUDE.md.render.now" || { ok=0; echo "    theirs leg (render-now) is not the NEW render"; }
  grep -q 'MY LOCAL EDIT'        "$run/incoming/CLAUDE.md.ours"        || { ok=0; echo "    ours leg lost the user's local edit"; }
  if [ -f "$cand" ]; then
    # theirs (render-NOW) must reach the candidate — the swap silently drops exactly this
    grep -q 'NEW upstream body line' "$cand" || { ok=0; echo "    candidate DROPPED the upstream delta — base/theirs swapped: the new render was treated as the common ancestor"; }
    grep -q 'extra new line'         "$cand" || { ok=0; echo "    candidate dropped the upstream added line"; }
    # ours must survive too
    grep -q 'MY LOCAL EDIT'          "$cand" || { ok=0; echo "    candidate dropped the user's ours-only content"; }
  else
    ok=0; echo "    no A1 candidate built"
  fi
  [ "$ok" = 1 ] && pass "A1 three-way leg order pinned (base=render-then, ours=user-now, theirs=render-now)" \
    || fail_ "A1 merge leg order" "see above"
  rm -rf "$b"
}

t_plan_dispatch_creates_run_folder() {   # killing test: # BL-109-PLAN dispatch
  local b; b="$(mktemp -d)"; local proj="$b/p"; mkdir -p "$proj/.claude"
  cat > "$proj/.claude/phase-state.json" <<EOF
{"project":"disp","track":"standard","deployment":"personal","current_phase":0}
EOF
  cat > "$proj/.claude/manifest.json" <<EOF
{"currency":{"schemaVersion":1,"soloFrameworkPath":"$LIB_ROOT","files":{},"renderBases":{"A1":{},"A2":{}},"hooks":{},"mcpProbe":{"context7":"absent"}}}
EOF
  ( cd "$proj" && bash "$LIB_ROOT/scripts/upgrade-project.sh" --plan ) >/dev/null 2>&1
  if ls -d "$proj"/docs/updates/*/UPDATE-PLAN.md >/dev/null 2>&1; then
    pass "--plan dispatch (# BL-109-PLAN) creates a run folder via the real upgrade-project.sh"
  else
    fail_ "plan dispatch" "no run folder — the # BL-109-PLAN dispatch did not fire"
  fi
  rm -rf "$b"
}

t_plan_blocked_under_sentinel() {
  local b; b="$(mktemp -d)"; local proj="$b/p"; mkdir -p "$proj/.claude"
  cat > "$proj/.claude/phase-state.json" <<EOF
{"project":"disp","track":"standard","deployment":"personal","current_phase":0}
EOF
  cat > "$proj/.claude/manifest.json" <<EOF
{"currency":{"schemaVersion":1,"soloFrameworkPath":"$LIB_ROOT","files":{},"renderBases":{"A1":{},"A2":{}},"hooks":{},"mcpProbe":{"context7":"absent"}}}
EOF
  echo '{"question":"pick","options":["a"],"offered_at":"now"}' > "$proj/.claude/pending-approval.json"
  local rc=0
  ( cd "$proj" && bash "$LIB_ROOT/scripts/upgrade-project.sh" --plan ) >/dev/null 2>&1 || rc=$?
  local ok=1
  [ "$rc" != 0 ] || { ok=0; echo "    --plan exited 0 under a sentinel (should block)"; }
  ls -d "$proj"/docs/updates/*/ >/dev/null 2>&1 && { ok=0; echo "    a run folder was created despite the sentinel"; }
  [ "$ok" = 1 ] && pass "--plan is frozen under a pending-approval sentinel (conservative I8 reading)" || fail_ "sentinel block" "see above"
  rm -rf "$b"
}

t_i11_payload_cross_product() {   # killing test: # BL-109-I11-PAYLOAD (verb arms)
  # THE CROSS-PRODUCT. Every I11 (class × verb) the engine can emit, in ONE run, each
  # asserted to carry a REAL diff payload (hunk header + a +/- content line) in its
  # consent section — never a heading over an empty code block.
  #
  # This is the test that would have caught all THREE hollow-fence bugs: the gate-script
  # diffstat-only (r1), the empty hook block (r1 fix round), and the empty renamed-gate
  # block (r2). Remove ANY verb's arm from _soif_plan_unified_diff and the payload guard
  # turns this RED — for that verb specifically, by name.
  local b; b="$(mktemp -d)"; mk_i11_matrix "$b"
  local run rc=0
  run="$(soif_plan_run "$PROJ" "$FW" "$FW/init.sh" "$b/nocdf" 2>"$b/err")" || rc=$?
  if [ "$rc" != 0 ] || [ -z "$run" ]; then
    fail_ "I11 payload cross-product" "plan run FAILED (rc=$rc) — payload guard fired: $(head -6 "$b/err" | tr '\n' ' ')"
    rm -rf "$b"; return
  fi
  local up="$run/UPDATE-PLAN.md" m="$run/manifest.json" ok=1 sec; sec="$b/sec"

  # The matrix really was produced (else every assertion below is vacuous).
  local gate_upd="fw-drift:scripts/pre-commit-gate.sh"
  local gate_add="add:scripts/run-phase3-validation.sh"
  local gate_ret="orphan:scripts/process-checklist.sh"
  local gate_ren_old="orphan:scripts/check-gate.sh"
  local gate_ren_new="add:scripts/check-phase-gate.sh"
  local hook_upd="hook-drift:commit-msg"
  local hook_add="hook-missing:pre-commit"

  # (verb, id) pairs — the matrix. Each must exist AND carry a payload.
  local pairs="update:$gate_upd add:$gate_add retire:$gate_ret rename:$gate_ren_old rename:$gate_ren_new update:$hook_upd add:$hook_add"
  local pair want_verb want_id got_verb
  for pair in $pairs; do
    want_verb="${pair%%:*}"; want_id="${pair#*:}"
    got_verb="$(jq -r --arg i "$want_id" '.items[] | select(.id==$i) | .verb' "$m" 2>/dev/null)"
    if [ -z "$got_verb" ]; then
      ok=0; echo "    MATRIX GAP: no item [$want_id] — the fixture did not produce the ($want_verb) row"; continue
    fi
    [ "$got_verb" = "$want_verb" ] || { ok=0; echo "    [$want_id] verb=$got_verb, expected $want_verb"; }
    # every one of them is I11 → item-consent, never batch
    [ "$(jq -r --arg i "$want_id" '.items[] | select(.id==$i) | .consent' "$m")" = "item" ] \
      || { ok=0; echo "    [$want_id] is NOT item-consent — I11 breach"; }
    # …and its consent section carries a REAL payload
    _i11_section "$up" "$want_id" > "$sec"
    if ! _has_payload "$sec"; then
      ok=0
      echo "    HOLLOW PAYLOAD: [$want_id] ($want_verb) — its I11 section promises a FULL diff but has no hunk header / no +/- content line"
    fi
  done

  # The rename pair shows BOTH sides: the old path as a removal, the new path as an
  # addition (the declared rendering — each checkbox shows what ticking THAT box does).
  _i11_section "$up" "$gate_ren_old" > "$sec"
  grep -q '^-moved-gate-body' "$sec" || { ok=0; echo "    rename OLD side does not show the file being removed"; }
  _i11_section "$up" "$gate_ren_new" > "$sec"
  grep -q '^+moved-gate-body' "$sec" || { ok=0; echo "    rename NEW side does not show the file being added"; }

  # The staged diffs/ artifact for a rename is non-empty too (same producer, same bug).
  local rdiff; rdiff="$(jq -r --arg i "$gate_ren_old" '.items[] | select(.id==$i) | .diff // empty' "$m")"
  if [ -n "$rdiff" ] && [ -f "$run/$rdiff" ]; then
    _has_payload "$run/$rdiff" || { ok=0; echo "    the staged diffs/ artifact for the rename is EMPTY"; }
  fi

  # CONTROLS — the fence stays narrow: ordinary scripts are still batch/diffstat.
  [ "$(jq -r '.items[] | select(.id=="fw-drift:scripts/foo.sh") | .consent' "$m")" = "batch" ] \
    || { ok=0; echo "    ordinary M update was escalated to item-consent (fence too broad)"; }
  grep -q '^### `fw-drift:scripts/foo.sh`' "$up" \
    && { ok=0; echo "    ordinary M update got a full-diff I11 section"; }

  [ "$ok" = 1 ] && pass "I11 payload cross-product: every (class × verb) consent section carries a REAL diff — update/add/retire/rename × {gate, hook}" \
    || fail_ "I11 payload cross-product" "see above"
  rm -rf "$b"
}

t_i11_empty_payload_hard_error() {   # killing test: # BL-109-I11-PAYLOAD (the guard body)
  # THE GUARD ITSELF. Two independent drives, both of which MUST hard-error:
  #
  #   (1) END-TO-END — a gate script whose upstream source is a ZERO-BYTE file. The add
  #       arm produces `diff -u /dev/null <empty>` → nothing. soif_plan_run must ABORT,
  #       name the item/class/verb, and leave NO run folder: a plan that cannot show the
  #       operator what they are consenting to must not offer the consent at all.
  #
  #   (2) A FUTURE VERB — a synthetic verb with no arm in _soif_plan_unified_diff, which
  #       is precisely how this bug class keeps arriving. It falls through `*)`, produces
  #       nothing, and must be caught BY CONSTRUCTION rather than by the next reviewer.
  #
  # Neuter _soif_plan_diff_has_payload and BOTH go green-instead-of-abort → RED.
  local b; b="$(mktemp -d)" ok=1

  # ── (1) end-to-end: empty upstream gate script ───────────────────────────────
  mk_i11_matrix "$b" 1
  local run rc=0
  run="$(soif_plan_run "$PROJ" "$FW" "$FW/init.sh" "$b/nocdf" 2>"$b/err")" || rc=$?
  [ "$rc" != 0 ] || { ok=0; echo "    soif_plan_run exited 0 with an EMPTY I11 payload — the hollow plan was offered"; }
  grep -q 'ABORT' "$b/err"                        || { ok=0; echo "    the abort is not loud (no ABORT on stderr)"; }
  grep -q 'add:scripts/run-phase3-validation.sh' "$b/err" || { ok=0; echo "    the abort does not NAME the offending item"; }
  grep -q 'class: M'                    "$b/err"  || { ok=0; echo "    the abort does not name the CLASS"; }
  grep -q 'verb:  add'                  "$b/err"  || { ok=0; echo "    the abort does not name the VERB"; }
  # FAIL CLOSED — no run folder, no UPDATE-PLAN, nothing to tick.
  if find "$PROJ/docs/updates" -name 'UPDATE-PLAN.md' 2>/dev/null | grep -q .; then
    ok=0; echo "    an UPDATE-PLAN.md survived the abort — a consent surface the operator cannot read"
  fi
  if [ -n "$run" ] && [ -d "$run" ]; then ok=0; echo "    the run folder survived the abort (not fail-closed)"; fi

  # ── (2) a FUTURE verb with no diff arm ──────────────────────────────────────
  # Drive the emitter directly with a rows file carrying an unknown verb on a gate path
  # whose project + framework copies are IDENTICAL (so even the `*)` fallback yields
  # nothing). No new verb can be added to the engine without a diff arm and stay silent.
  local b2; b2="$(mktemp -d)"; mk_i11_matrix "$b2"
  printf 'echo gate v2\n' > "$PROJ/scripts/pre-commit-gate.sh"      # identical to upstream
  local rows notices out err erc=0
  rows="$b2/rows"; notices="$b2/notices"; out="$b2/out"; err="$b2/err2"
  : > "$notices"
  # id \t class \t verb \t tier \t path \t consent \t added \t removed \t bshort
  printf 'fw-drift:scripts/pre-commit-gate.sh\tM\tfrobnicate\tenforcement\tscripts/pre-commit-gate.sh\titem\t0\t0\tabc1234\n' > "$rows"
  mkdir -p "$b2/run"
  _soif_plan_emit_update_plan "$b2/run" "runid" "$(date +%s)" "$FW" "$PIN" "abc1234" \
      "$PIN" true 1 "$rows" "$notices" "$PROJ" "$FW/init.sh" > "$out" 2>"$err" || erc=$?
  [ "$erc" != 0 ] || { ok=0; echo "    an UNKNOWN verb with no diff arm emitted a plan instead of aborting"; }
  grep -q 'frobnicate' "$err" || { ok=0; echo "    the abort does not name the unknown verb"; }
  grep -qF '```diff' "$out"   && { ok=0; echo "    an empty \`\`\`diff block was printed under an I11 heading — the hollow-payload lie"; }

  [ "$ok" = 1 ] && pass "an EMPTY I11 payload is a HARD ERROR: the plan aborts, names the item/class/verb, and leaves no run folder (a future verb with no diff arm trips it)" \
    || fail_ "I11 empty payload hard error" "see above"
  rm -rf "$b" "$b2"
}

t_retire_tier_derived_from_path() {   # killing test: # BL-109-PLAN-TIER
  # TIER IS A PROPERTY OF THE PATH, NOT THE VERB. The retire arm used to hard-code
  # `tier=enforcement` for every orphan, so retiring an ordinary script rendered as a ⚠
  # ENFORCEMENT item — a lie about what the operator is being shown, and one that
  # devalues the ⚠ on the items that really are enforcement machinery.
  local b; b="$(mktemp -d)"; mk_i11_matrix "$b"
  local run rc=0; run="$(soif_plan_run "$PROJ" "$FW" "$FW/init.sh" "$b/nocdf" 2>/dev/null)" || rc=$?
  if [ "$rc" != 0 ]; then fail_ "retire tier" "plan run failed (rc=$rc)"; rm -rf "$b"; return; fi
  local m="$run/manifest.json" ok=1

  # an ORDINARY script retire → informational, and NOT an I11 item (no full-diff section)
  [ "$(jq -r '.items[] | select(.id=="orphan:scripts/deadfile.sh") | .tier' "$m")" = "informational" ] \
    || { ok=0; echo "    retiring an ORDINARY script is still tagged enforcement tier"; }
  grep -q '^### `orphan:scripts/deadfile.sh`' "$run/UPDATE-PLAN.md" \
    && { ok=0; echo "    an ordinary-script retire got an I11 full-diff section"; }
  # a GATE-SCRIPT retire → enforcement (the predicate is not just returning a constant)
  [ "$(jq -r '.items[] | select(.id=="orphan:scripts/process-checklist.sh") | .tier' "$m")" = "enforcement" ] \
    || { ok=0; echo "    retiring a GATE script is NOT enforcement tier — the fence went blind"; }
  # …and a gate-script ADD is enforcement too (same predicate, other verb)
  [ "$(jq -r '.items[] | select(.id=="add:scripts/run-phase3-validation.sh") | .tier' "$m")" = "enforcement" ] \
    || { ok=0; echo "    a gate-script ADD is not enforcement tier"; }
  # both retires keep item-consent — a deletion is destructive whatever its tier
  [ "$(jq -r '.items[] | select(.id=="orphan:scripts/deadfile.sh") | .consent' "$m")" = "item" ] \
    || { ok=0; echo "    an ordinary retire lost item-consent (deletions are never batched)"; }
  [ "$ok" = 1 ] && pass "retire/add TIER is derived from the path (# BL-109-PLAN-TIER): ordinary → informational, gate script → enforcement" \
    || fail_ "retire tier derivation" "see above"
  rm -rf "$b"
}

t_payload_predicate_strictness() {   # killing test: # BL-109-I11-PAYLOAD (the predicate)
  # PIN THE GUARD'S STRICTNESS, NOT JUST ITS EXISTENCE (S3 review round 3).
  #
  # The payload guard WORKS: the round-2 verifier built its own (class × verb × tier)
  # cross-product against the real engine and found ZERO hollow payloads. But NOTHING
  # PINNED HOW STRICT IT IS — the same verifier weakened _soif_plan_diff_has_payload (down
  # to "any non-empty output") and all 22 plan tests and all 39 registry rows stayed GREEN.
  # A future edit could soften it to `grep -q .` and every test would still pass, and the
  # hollow-payload lie — the thing this guard exists to kill — would be back.
  #
  # That is the WEAK-TEST class, on the guard built to kill the weak-test class. So the
  # predicate is asserted DIRECTLY, on crafted inputs, in BOTH directions.
  #
  # The ACCEPT direction matters as much as the REJECT one: an OVER-strict predicate
  # aborts a legitimate plan, which is a denial-of-service on the operator's own updates.
  # The nasty case is a diff whose PAYLOAD is made of lines that LOOK like diff markers —
  # an added line whose text begins `+++` renders as `++++ …`, a removed line whose text
  # begins `---` renders as `---- …`, and a line containing `@@` renders as `+@@ …`. Those
  # are REAL changes to REAL files (TOML fences, diff snippets inside docs, this very
  # repo's own test fixtures) and they must be accepted, not mistaken for file headers or
  # hunk headers. Position, not spelling, is what distinguishes a marker from content:
  # markers precede the first `@@`, content follows it.
  local b; b="$(mktemp -d)" ok=1

  # ── REJECT: nothing here shows the operator a single changed line ───────────────
  : > "$b/r-empty"                                       # empty
  printf '   \n\t\n\n' > "$b/r-whitespace"               # whitespace only
  cat > "$b/r-headers-no-hunk" <<'EOF'
--- a/scripts/pre-commit-gate.sh
+++ b/scripts/pre-commit-gate.sh
EOF
  cat > "$b/r-hunk-no-content" <<'EOF'
--- a/scripts/pre-commit-gate.sh
+++ b/scripts/pre-commit-gate.sh
@@ -1,2 +1,2 @@
 echo gate
 exit 0
EOF
  cat > "$b/r-content-no-hunk" <<'EOF'
--- a/scripts/pre-commit-gate.sh
+++ b/scripts/pre-commit-gate.sh
-echo gate v1
+echo gate v2
EOF
  _pp_reject "empty output"                          "$b/r-empty"           || ok=0
  _pp_reject "whitespace-only output"                "$b/r-whitespace"      || ok=0
  _pp_reject "file headers with NO hunk header"      "$b/r-headers-no-hunk" || ok=0
  _pp_reject "a hunk header with NO +/- content"     "$b/r-hunk-no-content" || ok=0
  _pp_reject "+/- lines with NO hunk header"         "$b/r-content-no-hunk" || ok=0

  # ── ACCEPT: every one of these shows the operator a real changed line ───────────
  cat > "$b/a-minimal" <<'EOF'
--- a/f
+++ b/f
@@ -0,0 +1 @@
+hello
EOF
  cat > "$b/a-pure-add" <<'EOF'
--- /dev/null
+++ b/scripts/run-phase3-validation.sh
@@ -0,0 +1,2 @@
+#!/usr/bin/env bash
+echo phase3
EOF
  cat > "$b/a-pure-del" <<'EOF'
--- a/scripts/process-checklist.sh
+++ /dev/null
@@ -1,2 +0,0 @@
-#!/usr/bin/env bash
-echo checklist
EOF
  cat > "$b/a-one-line" <<'EOF'
--- a/scripts/pre-commit-gate.sh
+++ b/scripts/pre-commit-gate.sh
@@ -1 +1 @@
-echo gate v1
+echo gate v2
EOF
  # NASTY (1) — the ONLY content line is an ADDED line whose text starts with `+++`.
  cat > "$b/a-marker-add" <<'EOF'
--- a/docs/example.md
+++ b/docs/example.md
@@ -0,0 +1 @@
++++ toml front-matter fence
EOF
  # NASTY (2) — the ONLY content line is a REMOVED line whose text starts with `---`.
  cat > "$b/a-marker-del" <<'EOF'
--- a/docs/example.md
+++ b/docs/example.md
@@ -1 +0,0 @@
---- yaml front-matter fence
EOF
  # NASTY (3) — a content line that looks like a HUNK header (must not be mistaken for
  # one, must not be "double-counted" as both marker and content).
  cat > "$b/a-marker-hunk" <<'EOF'
--- a/docs/example.md
+++ b/docs/example.md
@@ -1 +1 @@
-@@ -1,2 +1,2 @@ old snippet
+@@ -3,4 +3,4 @@ new snippet
EOF
  # NASTY (4) — a first hunk with no content, a second hunk that carries the change.
  cat > "$b/a-multi-hunk" <<'EOF'
--- a/scripts/pre-commit-gate.sh
+++ b/scripts/pre-commit-gate.sh
@@ -1,2 +1,2 @@
 echo gate
 exit 0
@@ -9,1 +9,1 @@
-echo old
+echo new
EOF
  _pp_accept "a minimal real diff (hunk + one + line)"        "$b/a-minimal"     || ok=0
  _pp_accept "a pure addition"                                "$b/a-pure-add"    || ok=0
  _pp_accept "a pure deletion"                                "$b/a-pure-del"    || ok=0
  _pp_accept "a one-line change"                              "$b/a-one-line"    || ok=0
  _pp_accept "payload whose added line TEXT begins with +++"  "$b/a-marker-add"  || ok=0
  _pp_accept "payload whose removed line TEXT begins with ---" "$b/a-marker-del" || ok=0
  _pp_accept "payload whose lines look like HUNK headers"     "$b/a-marker-hunk" || ok=0
  _pp_accept "content in the SECOND hunk (first is context-only)" "$b/a-multi-hunk" || ok=0

  [ "$ok" = 1 ] && pass "the I11 payload PREDICATE's strictness is pinned in BOTH directions: hollow blocks rejected (empty/whitespace/headers-only/hunkless/contentless), real diffs accepted — including payload lines that LOOK like +++/---/@@ markers" \
    || fail_ "payload predicate strictness" "see above"
  rm -rf "$b"
}

t_missing_tracked_file_restored() {   # killing test: # BL-109-MISSING
  # THE MISDIAGNOSED ABORT (S3 review round 3, minor 1). freshness-detect's drift arm
  # compared the MANIFEST sha to the UPSTREAM sha and never checked that the project file
  # still EXISTS. So an operator who had locally deleted a tracked gate script (it stays in
  # currency.files) got a drift item whose `update` diff had no base — an EMPTY payload —
  # and the fail-closed payload guard then ABORTED THE WHOLE PLAN, blaming the payload/verb
  # instead of the true cause, and bricking every unrelated item in the run.
  #
  # DECISION (declared): a missing tracked file is a LEGITIMATE PLAN ITEM, offered back.
  # A deleted gate script is exactly the drift the operator most needs offered — refusing
  # would leave the project permanently unplannable until they hand-restored a file they
  # may not know is gone. It is emitted as `missing:<path>` with verb `add`, whose diff is
  # a real /dev/null → upstream addition, so the I11 payload contract is met by
  # construction. The MESSAGE names the TRUE cause. Nothing else in the plan is disturbed.
  local b; b="$(mktemp -d)" ok=1
  mk_i11_matrix "$b"
  rm -f "$PROJ/scripts/pre-commit-gate.sh"      # tracked GATE script, deleted locally

  # (a) the DETECTOR names the true cause — never a payload/verb misdiagnosis.
  local fresh; fresh="$(soif_freshness_detect "$PROJ" "$PROJ/.claude/manifest.json" "$FW" "$FW/init.sh" "$b/nocdf")"
  printf '%s\n' "$fresh" | grep -q '^missing:scripts/pre-commit-gate.sh' \
    || { ok=0; echo "    the detector emits no missing: item for a locally-deleted tracked file"; }
  printf '%s\n' "$fresh" | grep -q 'tracked file is missing from the project' \
    || { ok=0; echo "    the message does not name the TRUE cause"; }
  printf '%s\n' "$fresh" | grep -q '^fw-drift:scripts/pre-commit-gate.sh' \
    && { ok=0; echo "    the deleted file is STILL emitted as framework-drift (the misdiagnosis survives)"; }

  # (b) the PLAN completes — no abort, and the unrelated items are all still there.
  local run rc=0
  run="$(soif_plan_run "$PROJ" "$FW" "$FW/init.sh" "$b/nocdf" 2>"$b/err")" || rc=$?
  if [ "$rc" != 0 ]; then
    ok=0; echo "    the plan ABORTED on a locally-deleted tracked file (blast radius: every item)"
    sed -n '1,6p' "$b/err" | sed 's/^/      /'
  fi
  if [ "$rc" = 0 ] && [ -n "$run" ]; then
    local m="$run/manifest.json" up="$run/UPDATE-PLAN.md"
    [ "$(jq -r '.items[] | select(.id=="missing:scripts/pre-commit-gate.sh") | .verb' "$m")" = "add" ] \
      || { ok=0; echo "    the missing tracked file is not offered back as an add"; }
    [ "$(jq -r '.items[] | select(.id=="missing:scripts/pre-commit-gate.sh") | .tier' "$m")" = "enforcement" ] \
      || { ok=0; echo "    a missing GATE script is not enforcement tier"; }
    [ "$(jq -r '.items[] | select(.id=="missing:scripts/pre-commit-gate.sh") | .consent' "$m")" = "item" ] \
      || { ok=0; echo "    a missing GATE script was left batch-consentable (I11 breach)"; }
    # the I11 section carries a REAL payload — the whole upstream file, offered back.
    local sec="$b/sec"
    _i11_section "$up" "missing:scripts/pre-commit-gate.sh" > "$sec"
    _has_payload "$sec" || { ok=0; echo "    the missing-file consent section has NO diff payload"; }
    grep -q '^+echo gate v2' "$sec" || { ok=0; echo "    the restore diff does not show the upstream content being added"; }
    # NO BLAST RADIUS — the unrelated items survive.
    for other in "add:scripts/run-phase3-validation.sh" "orphan:scripts/deadfile.sh" "fw-drift:scripts/foo.sh"; do
      [ "$(jq -r --arg i "$other" '[.items[] | select(.id==$i)] | length' "$m")" = "1" ] \
        || { ok=0; echo "    unrelated item vanished from the plan: $other"; }
    done
  fi

  # (c) GONE BOTH SIDES — missing locally AND no longer shipped upstream. There is nothing
  # to restore and nothing on disk to retire, so it is a NOTICE, never a checkbox: an
  # `orphan` retire item here would have promised to delete a file that is already gone
  # (and its retire diff would be empty → the same hollow abort, one verb over).
  local b2; b2="$(mktemp -d)"; mk_i11_matrix "$b2"
  rm -f "$PROJ/scripts/process-checklist.sh"    # tracked, deleted locally, NOT shipped upstream
  local run2 rc2=0
  run2="$(soif_plan_run "$PROJ" "$FW" "$FW/init.sh" "$b2/nocdf" 2>"$b2/err")" || rc2=$?
  if [ "$rc2" != 0 ]; then
    ok=0; echo "    the plan ABORTED on a tracked file that is gone from BOTH sides"
    sed -n '1,6p' "$b2/err" | sed 's/^/      /'
  fi
  if [ "$rc2" = 0 ] && [ -n "$run2" ]; then
    [ "$(jq -r '[.items[] | select(.id | test("scripts/process-checklist.sh"))] | length' "$run2/manifest.json")" = "0" ] \
      || { ok=0; echo "    a file that is gone from BOTH sides was offered as a checkbox item"; }
    grep -q 'tracked file is missing from the project' "$run2/UPDATE-PLAN.md" \
      || { ok=0; echo "    the gone-both-sides case is silent — no notice names the true cause"; }
  fi

  [ "$ok" = 1 ] && pass "a locally-deleted TRACKED file is named for what it is (missing:) and OFFERED BACK as a real /dev/null → upstream add — never a payload/verb misdiagnosis, never a whole-plan abort" \
    || fail_ "missing tracked file" "see above"
  rm -rf "$b" "$b2"
}

t_abort_leaves_no_trace() {   # killing test: # BL-109-PLAN-NOTRACE
  # ABORT HYGIENE (S3 review round 3, minor 2). On a fail-closed payload abort the engine
  # discarded $RUN_DIR but left the docs/updates/ parent it had just created — so a
  # READ-ONLY --plan that refused to write a plan still mutated an otherwise-untouched
  # project tree. The assertion is a WHOLE-TREE fingerprint (files AND directories, so an
  # empty leftover dir cannot hide): after the abort the project is byte-identical.
  local b; b="$(mktemp -d)" ok=1
  mk_i11_matrix "$b" 1                        # empty upstream gate script → payload abort
  [ -d "$PROJ/docs" ] && { ok=0; echo "    fixture precondition: docs/ already exists"; }

  local before after rc=0
  before="$(_tree_fingerprint "$PROJ")"
  soif_plan_run "$PROJ" "$FW" "$FW/init.sh" "$b/nocdf" >/dev/null 2>"$b/err" || rc=$?
  [ "$rc" != 0 ] || { ok=0; echo "    the fixture did not abort — this test asserts nothing"; }
  after="$(_tree_fingerprint "$PROJ")"
  if [ "$before" != "$after" ]; then
    ok=0; echo "    the FAILED plan left a trace in the project tree:"
    diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") | sed 's/^/      /'
  fi
  [ -d "$PROJ/docs/updates" ] && { ok=0; echo "    docs/updates/ survived a fail-closed abort"; }

  # …and it NEVER removes a container that holds PRIOR runs (or one it did not create).
  local b2; b2="$(mktemp -d)"; mk_i11_matrix "$b2" 1
  mkdir -p "$PROJ/docs/updates/2020-01-01_deadbee_000000-1"
  printf 'a prior run\n' > "$PROJ/docs/updates/2020-01-01_deadbee_000000-1/UPDATE-PLAN.md"
  local before2 after2 rc2=0
  before2="$(_tree_fingerprint "$PROJ")"
  soif_plan_run "$PROJ" "$FW" "$FW/init.sh" "$b2/nocdf" >/dev/null 2>&1 || rc2=$?
  [ "$rc2" != 0 ] || { ok=0; echo "    the prior-runs fixture did not abort"; }
  after2="$(_tree_fingerprint "$PROJ")"
  [ "$before2" = "$after2" ] || { ok=0; echo "    the abort disturbed a docs/updates/ that holds PRIOR runs"; }
  [ -f "$PROJ/docs/updates/2020-01-01_deadbee_000000-1/UPDATE-PLAN.md" ] \
    || { ok=0; echo "    a PRIOR run folder was destroyed by an unrelated abort"; }

  [ "$ok" = 1 ] && pass "a fail-closed abort leaves NO trace: whole-tree fingerprint (files + dirs) byte-identical, docs/updates/ removed iff this run created it and it is empty — a container holding prior runs is never touched" \
    || fail_ "abort hygiene" "see above"
  rm -rf "$b" "$b2"
}

# ── registry + run ───────────────────────────────────────────────────────────
ALL_TESTS="t_folder_shape t_exclusive_mkdir t_verbs_and_rename t_retire_emitted \
t_grammar_pin t_base_sha_recorded t_rollup_shallow_fallback t_pin_absent_degrades \
t_a2_structural_only t_a1_candidate_placeholder_free t_a1_intake_candidate \
t_a1_placeholder_withheld t_a1_merge_leg_order t_i1_write_fence \
t_i1_fence_catches_stray_outside_run_folder t_hook_item_consent_full_diff \
t_i11_consent_scope_simultaneous_drift t_i11_payload_cross_product \
t_i11_empty_payload_hard_error t_payload_predicate_strictness \
t_retire_tier_derived_from_path t_missing_tracked_file_restored \
t_abort_leaves_no_trace \
t_plan_dispatch_creates_run_folder t_plan_blocked_under_sentinel"

echo "== tests/test-plan-staging.sh (LIB_ROOT=$LIB_ROOT) =="
if [ -n "$ONLY" ]; then
  for t in $ONLY; do "$t"; done
else
  for t in $ALL_TESTS; do "$t"; done
fi
echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

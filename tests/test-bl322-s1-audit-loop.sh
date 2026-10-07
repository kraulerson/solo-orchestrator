#!/usr/bin/env bash
# tests/test-bl322-s1-audit-loop.sh — `## BL-322:` S1, dogfood run 3's findings
# 16, 20 and 15 (Solo's halves).
#
# THE DEFECT. After every commit the user approved through the Development
# Guardrails (CDF 4.4.0: a question answered by option id, then a lone
# `git commit`), the next session start's scripts/detect-out-of-band-commits.sh
# wrote an `out_of_band_commit` row (`actor: user_terminal_inferred`) for it into
# the TRACKED .claude/bypass-audit.json: a wrong audit record, which also left
# that file modified (findings 16, 20). Solo's runtime files
# (.claude/tool-usage.json, .claude/last-checked-commit.txt) sat untracked in an
# adopted project (finding 15): init.sh's .gitignore template ignores them,
# adoption wrote no ignore rule.
#
# WHAT THIS DOES NOT FIX: the Guardrails' stop hook ("Uncommitted source
# changes"). Review round 1 measured the real stop-checklist.sh: a modified
# bypass-audit.json alone passes, and so do the two untracked runtime files
# alone; an untracked .claude/approvals.jsonl or .claude/tdd-warn-ledger.jsonl
# alone blocks, because its source-file test counts an unknown extension as
# source. That is the Guardrails' defect, handed to them; Solo does not ignore
# those logs.
#
# WHAT "PROTECTED" MEANS. The Guardrails' config-guard.sh refuses an Edit/Write
# naming .claude/approvals.jsonl (their settings also deny `Edit(...)` on it)
# and a Bash command whose text names it unless every command in it only
# reads; marker-guard.sh guards the approval marker (/tmp/.claude_evaluated_*)
# the same way. Both are lexical. Review round 1 got an exempted commit from the
# agent's own Bash three ways that pass every guard and Solo's commit check:
# `CLAUDECODE= bash ~/.claude-dev-framework/hooks/mark-evaluated.sh "ok"` (the
# override refuses only a non-empty CLAUDECODE), a synthetic prompt envelope
# piped into record-approval.sh twice, and `cd .claude && printf … >>
# approvals.jsonl`. So no approvals line proves a human approved, and nothing in
# a line is secret. This change adds no cheaper forgery than what already
# exempted a commit: before it every commit was flagged anyway (the
# claude-commits.jsonl ledger is never written), and a line appended to that
# ledger, or a `fixup!` or `Merge ` subject, already exempted one. What the
# checks enforce is the SHAPE of the Guardrails' real flow, so that their own
# records never exempt a commit the user did not approve: a commit line with no
# approval before it (D4, what a forged marker leaves), behind a pick that
# approved nothing (D5, D10), or behind an approval an earlier commit line
# already used (D6, D11). A row in .claude/bypass-audit.json, which nothing
# protects, exempts nothing (D7).
#
# CASES
#   D1  two approved, matched commits: no out-of-band row, and the tracked audit
#       file is byte-identical and clean in git (red on base)
#   D2  matched:false: an approval_mismatch row, and still an out-of-band row
#   D3  an approved commit, then one made from the user's terminal: one row,
#       for the terminal commit only
#   D4  a commit record with no approval before it (a forged marker): a row
#   D5  the approval before it approves nothing (the user picked "do not
#       commit"): a row
#   D6  one approval behind two commits (a reset, then the same tree again): a
#       row for the second
#   D7  an `approved_commit` row forged into .claude/bypass-audit.json: a row
#   D8  the user's own override (mark-evaluated.sh) approves too: no row
#   D9  a commit field that is not one SHA (a hand-written line carrying a
#       SHA among other text) exempts nothing: the set is matched whole, not
#       by word
#   D10 the user approved, was asked again and held (a pick that approves
#       nothing); the Guardrails keep their marker, so the agent's commit
#       passes their check: a row (review round 1, R-322-2; real hooks)
#   D11 a matched:false commit used the approval; the same tree committed again
#       after a reset: a row for the second
#   I1  init.sh's .gitignore template ignores both runtime files (init.sh is
#       READ as source here, never run)
#   A1  a real adoption writes .claude/.gitignore, commits it, leaves the
#       project's .gitignore as it was; both runtime files are ignored and stay
#       out of git status; and on that adoptee its own copy of the detector
#       writes no row for an approved commit, leaves the audit file unchanged,
#       and still records a terminal commit. The fixture commits use
#       --no-verify: the detector reads history and approvals.jsonl, not how a
#       commit was made
#   A2  an adoptee's own .claude/.gitignore is left exactly as it was, and the
#       run names both lines to add
#   M   mutants: each rewrites ONE marked line (or deletes one exact line) in a
#       mirror, checks the edit landed and still parses, and needs a named case
#       to go RED
#
# This file names init.sh on executed lines (I1 reads generate_gitignore's
# body) and never invokes it, so it is registered in the tests.yml unit lane by
# hand, like tests/test-bl253-adoption-state-parity.sh. Hermetic: temp dirs
# only, no network, no Guardrails clone (adoption runs with a seam that points
# at an empty folder), no MCP step. bash 3.2 safe.
set -uo pipefail
unset GITHUB_BASE_REF 2>/dev/null || true
export SOIF_ADOPT_MCP=off   # BL-311-MCP-SEAM

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

for t in jq git; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/bl322s1.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT INT TERM
newtmp() { mktemp -d "$WORK/tXXXXXX"; }
CASE_DETAIL=""

# ── fixtures ─────────────────────────────────────────────────────────────────
gitq() { git -C "$1" "${@:2}" >/dev/null 2>&1; }
# fxd DIR — a strict project whose audit log is TRACKED and clean, with the
# detector's baseline at HEAD (the file is untracked, as in a real project).
fxd() {
  local d="$1"
  mkdir -p "$d/.claude" || return 1
  gitq "$d" init -q . && gitq "$d" config user.email t@bl322.invalid && gitq "$d" config user.name T \
    && gitq "$d" config core.excludesFile /dev/null || return 1
  jq -n '{frameworkVersion: "4.4.0", enforcement_level: "strict"}' > "$d/.claude/manifest.json"
  jq -n '[{timestamp: "2026-10-07T01:19:22Z", session_id: null, type: "adoption_event", actor: "framework",
           enforcement_level_at_event: "n/a", details: {event: "adoption"}, user_response: "n/a", final_outcome: "recorded_only"}]' \
    > "$d/.claude/bypass-audit.json"
  printf 'seed\n' > "$d/seed.txt"
  gitq "$d" add seed.txt .claude/manifest.json .claude/bypass-audit.json && gitq "$d" commit -q --no-verify -m "chore: seed" || return 1
  git -C "$d" rev-parse HEAD > "$d/.claude/last-checked-commit.txt"
}
stage_change() { printf '%s\n' "$3" > "$1/$2" && gitq "$1" add "$2"; }   # DIR FILE TEXT
commit_now() { gitq "$1" commit -q --no-verify -m "$2"; }                 # DIR MESSAGE
# pick DIR APPROVES [override] — the line the Guardrails append when the user
# approves (CDF aba947b: record-approval.sh's pick record, or mark-evaluated.sh's
# override record, each `+ git_stage_state`). Prints the approved tree, which is
# also what their approval marker carries.
pick() {
  local d="$1" ap="$2" head tree
  head="$(git -C "$d" rev-parse -q --verify HEAD 2>/dev/null)" || head=none
  tree="$(git -C "$d" write-tree)" || return 1
  if [ "${3:-}" = override ]; then
    jq -nc --arg h "$head" --arg t "$tree" \
      '{event: "approval", source: "override", reason: "approved in my own terminal", picked_at: "2026-10-07T01:00:00Z",
        head: $h, tree: $t, hooks_digest: "hd", config_digest: "cd"}'
  else
    jq -nc --arg a "$ap" --arg h "$head" --arg t "$tree" \
      '{event: "approval", source: "pick", session_id: "s1", prompt_id: "p1", pick: "A1", approves: $a,
        question: "Save the staged change?", option_text: "Save it", sentinel_sha256: "x", picked_at: "2026-10-07T01:00:00Z",
        attended: "", head: $h, tree: $t, hooks_digest: "hd", config_digest: "cd"}'
  fi >> "$d/.claude/approvals.jsonl"
  printf '%s\n' "$tree"
}
# commit_rec DIR APPROVED_TREE — the line marker-tracker.sh appends after a
# commit made under an approval marker (CDF aba947b, verbatim jq).
commit_rec() {
  local d="$1" a="$2" c t
  c="$(git -C "$d" rev-parse HEAD)"; t="$(git -C "$d" rev-parse 'HEAD^{tree}')"
  jq -nc --arg c "$c" --arg a "$a" --arg t "$t" --arg now "2026-10-07T01:00:30Z" \
    '{event: "commit", commit: $c, approved_tree: $a, committed_tree: $t, matched: ($a == $t), at: $now}' \
    >> "$d/.claude/approvals.jsonl"
}
# approved_commit DIR FILE MSG — stage, the user approves, the agent commits.
approved_commit() {
  local tr
  stage_change "$1" "$2" "$3" || return 1
  tr="$(pick "$1" commit)" || return 1
  commit_now "$1" "$3" || return 1
  commit_rec "$1" "$tr"
}
det() { bash "$1/scripts/detect-out-of-band-commits.sh" "$2" </dev/null >/dev/null 2>&1; }   # FW DIR
oob() {   # DIR [SHA] — out-of-band rows (for SHA)
  jq --arg s "${2:-}" '[.[] | select(.type == "out_of_band_commit" and ($s == "" or .details.commit_sha == $s))] | length' "$1/.claude/bypass-audit.json" 2>/dev/null
}
mism() { jq --arg s "$2" '[.[] | select(.type == "approval_mismatch" and .details.commit == $s)] | length' "$1/.claude/bypass-audit.json" 2>/dev/null; }
rows() { jq -c '[.[] | .type + ":" + ((.details.commit_sha // .details.commit // "") | .[0:7])]' "$1/.claude/bypass-audit.json" 2>/dev/null; }

# ── D: the detector ──────────────────────────────────────────────────────────
case_D1() {   # two approved, matched commits — nothing written, the tracked audit file untouched
  local d snap h
  d="$(newtmp)/p"; fxd "$d" || { CASE_DETAIL="fixture"; return 1; }
  approved_commit "$d" a.txt "chore: update the Guardrails" || { CASE_DETAIL="fixture commit 1"; return 1; }
  approved_commit "$d" b.txt "docs: record the assessment" || { CASE_DETAIL="fixture commit 2"; return 1; }
  snap="$(newtmp)/audit.json"; cp "$d/.claude/bypass-audit.json" "$snap"
  det "$1" "$d"
  [ "$(oob "$d")" = 0 ] || { CASE_DETAIL="out-of-band rows for approved commits: $(rows "$d")"; return 1; }
  cmp -s "$snap" "$d/.claude/bypass-audit.json" || { CASE_DETAIL="the audit file changed: $(rows "$d")"; return 1; }
  [ -z "$(git -C "$d" status --porcelain -- .claude/bypass-audit.json)" ] || { CASE_DETAIL="git: $(git -C "$d" status --porcelain -- .claude/bypass-audit.json)"; return 1; }
  h="$(git -C "$d" rev-parse HEAD)"
  [ "$(cat "$d/.claude/last-checked-commit.txt")" = "$h" ] || { CASE_DETAIL="the baseline did not move to HEAD"; return 1; }
}
case_D2() {   # matched:false — the violation row, and the commit is not exempt
  local d tr c
  d="$(newtmp)/p"; fxd "$d" || { CASE_DETAIL="fixture"; return 1; }
  stage_change "$d" a.txt "approved" && tr="$(pick "$d" commit)" || { CASE_DETAIL="fixture"; return 1; }
  stage_change "$d" hook.txt "a git hook added this during the commit" && commit_now "$d" "chore: approved change" && commit_rec "$d" "$tr" \
    || { CASE_DETAIL="fixture commit"; return 1; }
  c="$(git -C "$d" rev-parse HEAD)"
  jq -e --arg c "$c" 'select(.event == "commit" and .commit == $c) | .matched == false' "$d/.claude/approvals.jsonl" >/dev/null 2>&1 \
    || { CASE_DETAIL="the fixture's record is not matched:false"; return 1; }
  det "$1" "$d"
  [ "$(mism "$d" "$c")" = 1 ] || { CASE_DETAIL="approval_mismatch rows: $(rows "$d")"; return 1; }
  [ "$(oob "$d" "$c")" = 1 ] || { CASE_DETAIL="a matched:false commit was exempted: $(rows "$d")"; return 1; }
}
case_D3() {   # an approved commit, then a terminal commit — one row, the terminal one's
  local d c1 c2
  d="$(newtmp)/p"; fxd "$d" || { CASE_DETAIL="fixture"; return 1; }
  approved_commit "$d" a.txt "chore: approved" || { CASE_DETAIL="fixture"; return 1; }
  c1="$(git -C "$d" rev-parse HEAD)"
  stage_change "$d" u.txt "typed in my own terminal" && commit_now "$d" "fix: from my terminal" || { CASE_DETAIL="fixture"; return 1; }
  c2="$(git -C "$d" rev-parse HEAD)"
  det "$1" "$d"
  [ "$(oob "$d" "$c2")" = 1 ] || { CASE_DETAIL="the terminal commit is not recorded: $(rows "$d")"; return 1; }
  [ "$(oob "$d" "$c1")" = 0 ] || { CASE_DETAIL="the approved commit is recorded: $(rows "$d")"; return 1; }
  [ "$(oob "$d")" = 1 ] || { CASE_DETAIL="rows: $(rows "$d")"; return 1; }
}
case_D4() {   # a genuine commit record with no approval before it — a forged marker
  local d c
  d="$(newtmp)/p"; fxd "$d" || { CASE_DETAIL="fixture"; return 1; }
  stage_change "$d" a.txt "nobody approved this" && commit_now "$d" "feat: unapproved" || { CASE_DETAIL="fixture"; return 1; }
  commit_rec "$d" "$(git -C "$d" rev-parse 'HEAD^{tree}')"
  c="$(git -C "$d" rev-parse HEAD)"
  det "$1" "$d"
  [ "$(oob "$d" "$c")" = 1 ] || { CASE_DETAIL="a lone commit record exempted the commit: $(rows "$d")"; return 1; }
}
case_D5() {   # the user picked the option that approves nothing; the agent committed that stage anyway
  local d tr c
  d="$(newtmp)/p"; fxd "$d" || { CASE_DETAIL="fixture"; return 1; }
  stage_change "$d" a.txt "held" && tr="$(pick "$d" none)" && commit_now "$d" "feat: held change" && commit_rec "$d" "$tr" \
    || { CASE_DETAIL="fixture"; return 1; }
  c="$(git -C "$d" rev-parse HEAD)"
  det "$1" "$d"
  [ "$(oob "$d" "$c")" = 1 ] || { CASE_DETAIL="a pick that approves nothing exempted the commit: $(rows "$d")"; return 1; }
}
case_D6() {   # one approval, two commits: reset, then the same tree committed again
  local d h tr c2
  d="$(newtmp)/p"; fxd "$d" || { CASE_DETAIL="fixture"; return 1; }
  h="$(git -C "$d" rev-parse HEAD)"
  stage_change "$d" a.txt "approved once" && tr="$(pick "$d" commit)" && commit_now "$d" "chore: approved" && commit_rec "$d" "$tr" \
    || { CASE_DETAIL="fixture"; return 1; }
  gitq "$d" reset -q --soft "$h" && commit_now "$d" "chore: approved, reworded" && commit_rec "$d" "$tr" || { CASE_DETAIL="fixture recommit"; return 1; }
  c2="$(git -C "$d" rev-parse HEAD)"
  [ "$(git -C "$d" rev-parse "$c2^{tree}")" = "$tr" ] || { CASE_DETAIL="the recommit's tree is not the approved one"; return 1; }
  det "$1" "$d"
  [ "$(oob "$d" "$c2")" = 1 ] || { CASE_DETAIL="one approval exempted two commits: $(rows "$d")"; return 1; }
}
case_D7() {   # a forged row in the audit file (which nothing protects) exempts nothing
  local d c
  d="$(newtmp)/p"; fxd "$d" || { CASE_DETAIL="fixture"; return 1; }
  stage_change "$d" a.txt "x" && commit_now "$d" "feat: unapproved" || { CASE_DETAIL="fixture"; return 1; }
  c="$(git -C "$d" rev-parse HEAD)"
  jq --arg c "$c" '. + [{timestamp: "2026-10-07T01:00:00Z", session_id: null, type: "approved_commit", actor: "framework",
        enforcement_level_at_event: "strict", details: {commit_sha: $c, commit: $c, matched: true}, user_response: "n/a", final_outcome: "recorded_only"}]' \
    "$d/.claude/bypass-audit.json" > "$d/.claude/a.tmp" && mv "$d/.claude/a.tmp" "$d/.claude/bypass-audit.json"
  det "$1" "$d"
  [ "$(oob "$d" "$c")" = 1 ] || { CASE_DETAIL="a row in the audit file exempted the commit: $(rows "$d")"; return 1; }
}
case_D8() {   # the user's own override approves a commit too
  local d tr
  d="$(newtmp)/p"; fxd "$d" || { CASE_DETAIL="fixture"; return 1; }
  stage_change "$d" a.txt "x" && tr="$(pick "$d" commit override)" && commit_now "$d" "chore: approved in the terminal" && commit_rec "$d" "$tr" \
    || { CASE_DETAIL="fixture"; return 1; }
  det "$1" "$d"
  [ "$(oob "$d")" = 0 ] || { CASE_DETAIL="an override-approved commit was recorded: $(rows "$d")"; return 1; }
}

case_D9() {   # a commit field that smuggles a SHA among other text
  local d tr c
  d="$(newtmp)/p"; fxd "$d" || { CASE_DETAIL="fixture"; return 1; }
  stage_change "$d" a.txt "x" && tr="$(pick "$d" commit)" && commit_now "$d" "feat: x" || { CASE_DETAIL="fixture"; return 1; }
  c="$(git -C "$d" rev-parse HEAD)"
  jq -nc --arg c "0000000 $c" --arg t "$tr" '{event: "commit", commit: $c, approved_tree: $t, committed_tree: $t, matched: true, at: "x"}' \
    >> "$d/.claude/approvals.jsonl"
  det "$1" "$d"
  [ "$(oob "$d" "$c")" = 1 ] || { CASE_DETAIL="a SHA inside a longer commit field exempted the commit: $(rows "$d")"; return 1; }
}
case_D10() {   # approved, then held: the marker survives the hold, the commit is not approved
  local d tr c
  d="$(newtmp)/p"; fxd "$d" || { CASE_DETAIL="fixture"; return 1; }
  stage_change "$d" a.txt "x" && tr="$(pick "$d" commit)" && pick "$d" none >/dev/null \
    && commit_now "$d" "feat: committed after the user held" && commit_rec "$d" "$tr" || { CASE_DETAIL="fixture"; return 1; }
  c="$(git -C "$d" rev-parse HEAD)"
  det "$1" "$d"
  [ "$(oob "$d" "$c")" = 1 ] || { CASE_DETAIL="a commit after the user held was exempted: $(rows "$d")"; return 1; }
}
case_D11() {   # a matched:false commit used the approval; the approved tree committed again after a reset
  local d h tr c2
  d="$(newtmp)/p"; fxd "$d" || { CASE_DETAIL="fixture"; return 1; }
  h="$(git -C "$d" rev-parse HEAD)"
  stage_change "$d" a.txt "approved" && tr="$(pick "$d" commit)" || { CASE_DETAIL="fixture"; return 1; }
  stage_change "$d" hook.txt "a git hook added this" && commit_now "$d" "chore: c1" && commit_rec "$d" "$tr" || { CASE_DETAIL="fixture c1"; return 1; }
  gitq "$d" reset -q --soft "$h" && gitq "$d" rm -q --cached hook.txt && commit_now "$d" "chore: c2" && commit_rec "$d" "$tr" \
    || { CASE_DETAIL="fixture c2"; return 1; }
  c2="$(git -C "$d" rev-parse HEAD)"
  [ "$(git -C "$d" rev-parse "$c2^{tree}")" = "$tr" ] || { CASE_DETAIL="c2's tree is not the approved one"; return 1; }
  det "$1" "$d"
  [ "$(oob "$d" "$c2")" = 1 ] || { CASE_DETAIL="an approval used by a matched:false commit exempted a second one: $(rows "$d")"; return 1; }
}

# ── I: init.sh's .gitignore ──────────────────────────────────────────────────
RUNTIME_FILES=".claude/last-checked-commit.txt .claude/tool-usage.json"
ignored_all() {   # DIR — git ignores every runtime file's path (check-ignore needs no file there)
  local d="$1" f bad=""
  for f in $RUNTIME_FILES; do
    git -C "$d" check-ignore -q -- "$f" 2>/dev/null || bad="$bad $f"
  done
  [ -z "$bad" ] || { CASE_DETAIL="not ignored:$bad"; return 1; }
}
case_I1() {   # init.sh copies the template; the template ignores both files
  local d body
  body="$(awk '/^generate_gitignore\(\) \{/{f=1} f{print} f&&/^\}/{exit}' "$1/init.sh")"
  grep -qF 'cp "$SCRIPT_DIR/templates/generated/gitignore-base.tmpl" .gitignore' <<< "$body" \
    || { CASE_DETAIL="init.sh's generate_gitignore no longer copies the template"; return 1; }
  d="$(newtmp)/p"; mkdir -p "$d" && gitq "$d" init -q . && gitq "$d" config core.excludesFile /dev/null || { CASE_DETAIL="fixture"; return 1; }
  cp "$1/templates/generated/gitignore-base.tmpl" "$d/.gitignore" || { CASE_DETAIL="no template"; return 1; }
  ignored_all "$d"
}

# ── A: adoption ──────────────────────────────────────────────────────────────
# The adoptee and answers of tests/test-bl253-adoption-state-parity.sh (a small
# node project; the tier, the track, four confirmations), plus a .gitignore of
# its own. The scanner probe is pinned to `sh` and the Guardrails seam to an
# empty folder, so nothing depends on what the host has installed.
mk_adoptee() {
  local p="$1"
  mkdir -p "$p/src" "$p/docs" || return 1
  gitq "$p" init -q . && gitq "$p" config user.email bl322@test.invalid && gitq "$p" config user.name "BL322 Test" \
    && gitq "$p" config core.excludesFile /dev/null || return 1
  printf '{"name":"acme-api","scripts":{"test":"npm test"}}\n' > "$p/package.json"
  printf '# acme-api\n' > "$p/README.md"
  printf '# What this is for\n\nInvoice reconciliation for small firms.\n' > "$p/docs/product.md"
  printf 'node_modules/\n*.log\n' > "$p/.gitignore"
  gitq "$p" add -A && gitq "$p" commit -q --no-verify -m "chore: their own history"
}
REPORT=""
scan_once() {
  [ -n "$REPORT" ] && return 0
  local t="$WORK/scan-template"
  mk_adoptee "$t" || return 1
  bash "$REPO_ROOT/scripts/scout.sh" --root "$t" --out "$WORK/scan" </dev/null >/dev/null 2>&1 || return 1
  [ -s "$WORK/scan/scout-report.json" ] && REPORT="$WORK/scan/scout-report.json"
}
RUN_RC=0; RUN_OUT=""
run_adopt() {   # FW DIR
  RUN_RC=0; RUN_OUT="$(dirname "$2")/adopt.out"
  ( cd "$2" && printf '1\nstandard\n1\n1\n1\n1\n' | env SOIF_ADOPT_SCANNER_BIN=sh SOIF_ADOPT_QDRANT=no \
      SOIF_ADOPT_GUARDRAILS_DIR="$WORK/no-guardrails" bash "$1/scripts/adopt-project.sh" --scan-report "$REPORT" ) \
    > "$RUN_OUT" 2>&1 || RUN_RC=$?
}
case_A1() {   # adoption writes and commits .claude/.gitignore; on the adoptee, its own detector
  local p before snap c
  scan_once || { CASE_DETAIL="Scout produced no report"; return 1; }
  p="$(newtmp)/p"; mk_adoptee "$p" || { CASE_DETAIL="adoptee"; return 1; }
  before="$(newtmp)/gitignore"; cp "$p/.gitignore" "$before"
  run_adopt "$1" "$p"
  [ "$RUN_RC" -eq 0 ] || { CASE_DETAIL="adoption rc $RUN_RC: $(grep -E 'BLOCKED|REFUSED|FAIL' "$RUN_OUT" | head -1)"; return 1; }
  git -C "$p" ls-files --error-unmatch .claude/.gitignore >/dev/null 2>&1 || { CASE_DETAIL="no .claude/.gitignore in the adoption commit"; return 1; }
  [ -z "$(git -C "$p" status --porcelain -- .claude/.gitignore)" ] || { CASE_DETAIL="the committed .claude/.gitignore differs from the file"; return 1; }
  cmp -s "$before" "$p/.gitignore" || { CASE_DETAIL="the project's own .gitignore changed"; return 1; }
  ignored_all "$p" || return 1
  # The adoptee's own copy of the detector: the first session start sets the
  # baseline; an approved commit; the next session start.
  bash "$p/scripts/detect-out-of-band-commits.sh" "$p" </dev/null >/dev/null 2>&1
  [ -s "$p/.claude/last-checked-commit.txt" ] || { CASE_DETAIL="the adoptee's detector set no baseline"; return 1; }
  printf '{"calls":[]}\n' > "$p/.claude/tool-usage.json"   # what the MCP tracker leaves after a call
  approved_commit "$p" src/fix.txt "fix: the approved change" || { CASE_DETAIL="approved commit"; return 1; }
  snap="$(newtmp)/audit.json"; cp "$p/.claude/bypass-audit.json" "$snap"
  bash "$p/scripts/detect-out-of-band-commits.sh" "$p" </dev/null >/dev/null 2>&1
  [ "$(oob "$p")" = 0 ] || { CASE_DETAIL="the approved commit was recorded: $(rows "$p")"; return 1; }
  cmp -s "$snap" "$p/.claude/bypass-audit.json" || { CASE_DETAIL="the adoptee's audit file changed: $(rows "$p")"; return 1; }
  [ -z "$(git -C "$p" status --porcelain -- $RUNTIME_FILES)" ] || { CASE_DETAIL="git status shows: $(git -C "$p" status --porcelain -- $RUNTIME_FILES | tr '\n' '|')"; return 1; }
  # The detector is live there: a commit from the user's own terminal is still recorded.
  stage_change "$p" src/term.txt "terminal" && commit_now "$p" "fix: from my terminal" || { CASE_DETAIL="terminal commit"; return 1; }
  c="$(git -C "$p" rev-parse HEAD)"
  bash "$p/scripts/detect-out-of-band-commits.sh" "$p" </dev/null >/dev/null 2>&1
  [ "$(oob "$p" "$c")" = 1 ] || { CASE_DETAIL="the adoptee's detector recorded no terminal commit: $(rows "$p")"; return 1; }
}
case_A2() {   # an adoptee's own .claude/.gitignore is left as it was
  local p theirs named=""
  scan_once || { CASE_DETAIL="Scout produced no report"; return 1; }
  p="$(newtmp)/p"; mk_adoptee "$p" || { CASE_DETAIL="adoptee"; return 1; }
  mkdir -p "$p/.claude" && printf '/my-cache/\n' > "$p/.claude/.gitignore" && gitq "$p" add .claude/.gitignore \
    && gitq "$p" commit -q --no-verify -m "chore: my ignore rule" || { CASE_DETAIL="adoptee"; return 1; }
  theirs="$(newtmp)/theirs"; cp "$p/.claude/.gitignore" "$theirs"
  run_adopt "$1" "$p"
  [ "$RUN_RC" -eq 0 ] || { CASE_DETAIL="adoption rc $RUN_RC: $(grep -E 'BLOCKED|REFUSED|FAIL' "$RUN_OUT" | head -1)"; return 1; }
  cmp -s "$theirs" "$p/.claude/.gitignore" || { CASE_DETAIL="theirs was changed: $(tr '\n' '|' < "$p/.claude/.gitignore")"; return 1; }
  [ -z "$(git -C "$p" diff HEAD~1 HEAD -- .claude/.gitignore)" ] || { CASE_DETAIL="the adoption commit changed theirs"; return 1; }
  grep -qF '.claude/.gitignore is already yours' "$RUN_OUT" || { CASE_DETAIL="the run does not say it was left alone"; return 1; }
  named="$(grep -E '(^|[ :])/last-checked-commit\.txt' "$RUN_OUT")"
  grep -qE '(^|[ :])/tool-usage\.json' <<< "$named" \
    || { CASE_DETAIL="the run does not name both lines to add (/last-checked-commit.txt, /tool-usage.json)"; return 1; }
}

check() {   # LABEL CASE
  CASE_DETAIL=""
  if "$2" "$REPO_ROOT"; then pass "$1"; else fail_ "$1" "${CASE_DETAIL:-failed}"; fi
}

echo "=== D — the out-of-band detector ==="
check "D1: two approved, matched commits: no out-of-band row; the tracked audit file byte-identical and clean" case_D1
check "D2: matched:false: an approval_mismatch row, and the commit is still out of band" case_D2
check "D3: an approved commit, then a terminal commit: one row, for the terminal commit" case_D3
check "D4: a commit record with no approval before it (a forged marker): still out of band" case_D4
check "D5: the approval before it approves nothing: still out of band" case_D5
check "D6: one approval behind two commits: the second is out of band" case_D6
check "D7: an approved_commit row forged into bypass-audit.json: still out of band" case_D7
check "D8: the user's own override approves a commit: no row" case_D8
check "D9: a commit field that is not one SHA exempts nothing" case_D9
check "D10: approved, then held (a pick that approves nothing): the commit is out of band" case_D10
check "D11: an approval used by a matched:false commit exempts no second commit of its tree" case_D11
echo "=== I — init.sh's .gitignore ==="
check "I1: init.sh copies the template, and it ignores both runtime files" case_I1
echo "=== A — adoption ==="
check "A1: adoption writes and commits .claude/.gitignore; theirs unchanged; both ignored; the adoptee's detector skips an approved commit" case_A1
check "A2: an adoptee's own .claude/.gitignore is left exactly as it was, and the run names both lines to add" case_A2

# ── M: mutants ───────────────────────────────────────────────────────────────
mk_mirror() {   # SRC DST — scripts, templates and init.sh: enough for every case
  mkdir -p "$2" && cp -Rp "$1/scripts" "$1/templates" "$1/init.sh" "$2/"
}
mutate() {   # FILE MARKER REPLACEMENT — exactly one line ends in MARKER; it now reads REPLACEMENT; still parses
  local f="$1" mark="$2" repl="$3" n=""
  [ -f "$f" ] || { echo "no such file: $f"; return 1; }
  n="$(MARK="$mark" awk 'BEGIN{c=0; m=ENVIRON["MARK"]} length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m {c++} END{print c}' "$f")"
  [ "$n" = "1" ] || { echo "marker '$mark' ends $n line(s) of $f (need 1)"; return 1; }
  MARK="$mark" REPL="$repl" awk '{ m=ENVIRON["MARK"]
      if (length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m) print ENVIRON["REPL"]; else print }' \
    "$f" > "$f.mut" && cat "$f.mut" > "$f" && rm -f "$f.mut"
  grep -qF -- "$mark" "$f" && { echo "marker still present after the edit"; return 1; }
  [ "$(grep -cxF -- "$repl" "$f")" -ge 1 ] || { echo "replacement did not land"; return 1; }
  bash -n "$f" 2>/dev/null || { echo "mutant does not parse"; return 1; }
  return 0
}
drop_line() {   # FILE LINE — exactly one line equals LINE; it is deleted
  local f="$1" line="$2"
  [ "$(grep -cxF -- "$line" "$f")" = 1 ] || { echo "'$line' is not exactly one line of $f"; return 1; }
  LINE="$line" awk '$0 != ENVIRON["LINE"]' "$f" > "$f.mut" && cat "$f.mut" > "$f" && rm -f "$f.mut"
  [ "$(grep -cxF -- "$line" "$f")" = 0 ] || { echo "the line is still there"; return 1; }
}
run_mutant() {   # ID WHAT KILLER MIRROR
  local rc=0
  CASE_DETAIL=""
  "$3" "$4" || rc=$?
  if [ "$rc" -eq 0 ]; then fail_ "$1" "$2 — SURVIVED: ${3#case_} still passes against the mutant"
  else pass "$1 (MUTATION) — $2: killed by ${3#case_} (${CASE_DETAIL:-failed})"; fi
}
mutant() {   # ID FILE MARKER REPLACEMENT KILLER WHAT
  local m why
  m="$(newtmp)/mirror"
  mk_mirror "$REPO_ROOT" "$m" || { fail_ "$1" "could not build a mirror"; return; }
  why="$(mutate "$m/$2" "$3" "$4")" || { fail_ "$1" "mutant did not land: $why"; return; }
  run_mutant "$1" "$6" "$5" "$m"
}
mutant_drop() {   # ID FILE LINE KILLER WHAT
  local m why
  m="$(newtmp)/mirror"
  mk_mirror "$REPO_ROOT" "$m" || { fail_ "$1" "could not build a mirror"; return; }
  why="$(drop_line "$m/$2" "$3")" || { fail_ "$1" "mutant did not land: $why"; return; }
  run_mutant "$1" "$5" "$4" "$m"
}
echo "=== M — mutants ==="
DET=scripts/detect-out-of-band-commits.sh
mutant M1 "$DET" '# BL-322-OOB-APPROVED' '  :' case_D1 "approved commits are recorded as out of band again"
mutant M2 "$DET" '# BL-322-APPROVED-EXACT' '    *" "?*) return 0 ;;' case_D3 "one approved commit exempts every commit"
mutant M3 "$DET" '# BL-322-APPROVED-MATCHED' '            and true' case_D2 "a commit that is not the approved change is exempt"
mutant M4 "$DET" '# BL-322-APPROVED-PICK' '        (if true' case_D4 "a commit record alone (a forged marker) exempts"
mutant M5 "$DET" '# BL-322-APPROVED-APPROVES' '        (if true then .open = $e' case_D5 "a pick that approves nothing exempts"
mutant M6 "$DET" '# BL-322-APPROVED-ONCE' '        | .' case_D6 "one approval exempts every later commit of its tree"
mutant M12 "$DET" '# BL-322-APPROVED-HOLD' '         else . end)' case_D10 "a pick that approves nothing leaves the approval open"
mutant M13 "$DET" '# BL-322-APPROVED-ONCE' '        | .open = (if $e.matched == true then null else .open end)' case_D11 "only a matched commit uses up the approval"
mutant M11 "$DET" '# BL-322-APPROVED-SHA' '         then .ok += [$e.commit | tostring] else . end)' case_D9 "a commit field is split into words, so a SHA inside it counts"
SES=scripts/lib/adopt/adopt-session.sh
mutant M7 "$SES" '# BL-322-ADOPT-IGNORE-WRITE' '    :' case_A1 "adoption writes no ignore rule"
mutant M8 "$SES" '# BL-322-ADOPT-IGNORE-KEEP' '  if false; then' case_A2 "adoption writes over the adoptee's own .claude/.gitignore"
mutant_drop M14 "$SES" '    adopt_note "two lines to it: /last-checked-commit.txt and /tool-usage.json"' case_A2 "the kept-theirs note stops naming the two lines"
TPL=templates/generated/gitignore-base.tmpl
mutant_drop M9 "$TPL" '.claude/tool-usage.json' case_I1 "init.sh's template stops ignoring the MCP tool ledger"
mutant_drop M10 "$TPL" '.claude/last-checked-commit.txt' case_I1 "init.sh's template stops ignoring the detector's baseline"

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]

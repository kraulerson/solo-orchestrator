#!/usr/bin/env bash
# tests/test-brownfield-wp9d-window-rehearsal.sh
#
# WP9d items (4) and (7), per ADOPT-002-ARCH v2.2 §10-WP9d.
#
# (4) THE ADOPTION WINDOW. `## BL-291:`, measured on `579b0b0`: when the
# adoptee's own pre-commit hook rejects the adoption commit — the likely case
# for any brownfield project with lint-staged, prettier or commitlint, because
# the design keeps those hooks in place BY DECISION so they judge the commit —
# the project is left with 83 files written, the manifest stamped `adopted:
# true` in the working copy, HEAD unmoved, the index still holding every path,
# and no commit-msg hook. A bare re-run then refuses it as ALREADY ADOPTED and
# advises `scripts/resume.sh`, which is the wrong pointer for a project whose
# adoption never landed. The stamp's own bound calls that state the adoption
# window and reports EXEMPT, so every commit made from it is TDD-exempt until
# someone commits the manifest by hand.
#
# The package's answer: a `write_set` stage persists what was written, arm 1
# gains a sub-arm that recognises the window and names `--finish`, and
# `--finish` re-stages exactly that set and commits. NEVER `git add -A` — the
# operator's own uncommitted work must not be swept in, which is the property
# `# BF-ADOPT-STAGE-EXPLICIT` exists for and which a fallback would destroy.
#
# (7) THE REHEARSAL BOUND. `## BL-294:`: `adopt_prewrite_preflight` copies the
# whole tree including `.git/objects` with no bound and no cost statement. On
# this repository that is 57 MB and 0.43 s; on a real brownfield repository
# with a multi-GB history it doubles disk use on the system volume AFTER every
# question has been answered, and the only failure message names disk space.
#
# Hermetic: throwaway repositories under one temp dir. bash 3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRIVER="$REPO_ROOT/scripts/adopt-project.sh"

PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip_() { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'chmod -R u+rwX "$TOPTMP" 2>/dev/null; rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/fixXXXXXX"; }

mk_adoptee() {
  local p="$1"
  mkdir -p "$p/src" "$p/docs" || return 1
  ( cd "$p" && git init -q --initial-branch=main . 2>/dev/null || git init -q . ) || return 1
  git -C "$p" symbolic-ref HEAD refs/heads/main >/dev/null 2>&1
  git -C "$p" config user.email "wp9d@test.invalid" >/dev/null 2>&1
  git -C "$p" config user.name  "WP9d Test" >/dev/null 2>&1
  git -C "$p" config core.excludesFile /dev/null >/dev/null 2>&1
  printf '{"name":"acme-api","scripts":{"test":"npm test"}}\n' > "$p/package.json"
  printf '# acme-api\n' > "$p/README.md"
  printf '# What this is for\n\nInvoice reconciliation.\n' > "$p/docs/product.md"
  printf '# Architecture\n\nA node service.\n' > "$p/docs/architecture.md"
  ( cd "$p" && git add -A && git commit -q -m "chore: their own history" ) >/dev/null 2>&1 || return 1
  return 0
}

TEMPLATE="$(newtmp)/template"; REPORT=""
if mk_adoptee "$TEMPLATE" \
   && bash "$REPO_ROOT/scripts/scout.sh" --root "$TEMPLATE" --out "$TOPTMP/scan" >/dev/null 2>&1 \
   && [ -s "$TOPTMP/scan/scout-report.json" ]; then
  REPORT="$TOPTMP/scan/scout-report.json"
else
  echo "  [FAIL] setup — scripts/scout.sh produced no report"
  echo ""; echo "Results: 0 passed, 1 failed, 0 skipped"; exit 1
fi

_ans() { printf '1\n1\n1\n1\n1\n'; }
RUN_RC=0; RUN_OUT=""; RUN_ERR=""
run_in() {                        # run_in <cwd> [extra driver args...]
  local dir="$1"; shift
  local a="$TOPTMP/a.$$.$RANDOM"; _ans > "$a"
  RUN_RC=0; RUN_OUT="$TOPTMP/o.$$.$RANDOM"; RUN_ERR="$TOPTMP/e.$$.$RANDOM"
  ( cd "$dir" && bash "$DRIVER" --scan-report "$REPORT" "$@" ) < "$a" > "$RUN_OUT" 2> "$RUN_ERR" || RUN_RC=$?
  return 0
}
commits() { git -C "$1" rev-list --count HEAD 2>/dev/null || echo 0; }
head_adopted() { git -C "$1" show "HEAD:.claude/manifest.json" 2>/dev/null | grep -q '"adopted"[[:space:]]*:[[:space:]]*true'; }
WS=".claude/adoption/write-set.txt"

# ── the window fixture: the adoptee's own pre-commit hook refuses ───────────
mk_window() {                     # mk_window <dir> -> leaves the project IN the window
  local p="$1"
  mk_adoptee "$p" || return 1
  printf '#!/bin/sh\nexit 1\n' > "$p/.git/hooks/pre-commit"
  chmod +x "$p/.git/hooks/pre-commit"
  run_in "$p"
  return 0
}

echo "=== WIN — the adoption window (item 4) ==="

W1="$(newtmp)/p"; mkdir -p "$W1"; mk_window "$W1"
w1_before=$(commits "$W1")
if [ "$RUN_RC" -ne 0 ] && [ "$w1_before" -eq 1 ] && [ -f "$W1/$WS" ]; then
  # the set must list every written path AND ITSELF: a set that omits its own
  # file cannot be re-staged completely by --finish.
  w1_n=$(grep -c . "$W1/$WS" 2>/dev/null || echo 0)
  case "$w1_n" in ''|*[!0-9]*) w1_n=0 ;; esac
  w1_self=$(grep -cxF "$WS" "$W1/$WS" 2>/dev/null || echo 0)
  case "$w1_self" in ''|*[!0-9]*) w1_self=0 ;; esac
  w1_missing=0
  while IFS= read -r rel; do [ -n "$rel" ] || continue; [ -e "$W1/$rel" ] || w1_missing=$((w1_missing+1)); done < "$W1/$WS"
  if [ "$w1_n" -gt 50 ] && [ "$w1_self" -eq 1 ] && [ "$w1_missing" -eq 0 ]; then
    pass "WIN1: a hook-rejected adoption commit leaves $WS listing $w1_n path(s), including itself, every one on disk"
  else
    fail_ "WIN1" "paths=$w1_n (want >50) lists-itself=$w1_self (want 1) missing-on-disk=$w1_missing (want 0)"
  fi
else
  fail_ "WIN1" "rc=$RUN_RC commits=$w1_before (want 1) write-set=$([ -f "$W1/$WS" ] && echo present || echo ABSENT)"
fi

# WIN2 — the bare re-run must recognise the window, not report "already adopted".
run_in "$W1"
if [ "$RUN_RC" -ne 0 ] && grep -qF -- "--finish" "$RUN_OUT" "$RUN_ERR" 2>/dev/null \
   && ! grep -q 'already been adopted' "$RUN_OUT" "$RUN_ERR" 2>/dev/null; then
  pass "WIN2: a re-run inside the window names --finish and does NOT claim the project is already adopted"
else
  fail_ "WIN2" "rc=$RUN_RC names-finish=$(grep -cF -- '--finish' "$RUN_OUT" "$RUN_ERR" 2>/dev/null | awk -F: '{s+=$1} END{print s+0}') says-already-adopted=$(grep -c 'already been adopted' "$RUN_OUT" "$RUN_ERR" 2>/dev/null | awk -F: '{s+=$1} END{print s+0}')"
fi

# WIN3 — --finish completes it, and the operator's own dirty file is NOT swept in.
rm -f "$W1/.git/hooks/pre-commit"
printf 'my own work in progress\n' > "$W1/NOTES.txt"
run_in "$W1" --finish
w3_commits=$(commits "$W1")
w3_notes_tracked=0; git -C "$W1" ls-files --error-unmatch NOTES.txt >/dev/null 2>&1 && w3_notes_tracked=1
w3_hook=0; [ -f "$W1/.git/hooks/commit-msg" ] && w3_hook=1
if [ "$RUN_RC" -eq 0 ] && [ "$w3_commits" -eq 2 ] && head_adopted "$W1" && [ "$w3_hook" -eq 1 ] && [ "$w3_notes_tracked" -eq 0 ]; then
  pass "WIN3: --finish lands the adoption commit, the committed manifest is adopted, the gate is installed, and the operator's own untracked file stays out of it"
else
  fail_ "WIN3" "rc=$RUN_RC commits=$w3_commits (want 2) head-adopted=$(head_adopted "$W1" && echo 1 || echo 0) hook=$w3_hook notes-swept-in=$w3_notes_tracked (want 0)"
fi

# WIN4 — --finish on a LANDED adoption is refused; it is not a second commit.
run_in "$W1" --finish
# The count alone does not discriminate: with the window re-derivation removed,
# --finish reaches `git commit` with an empty index, git refuses, and the count
# is still 2. Assert the REASON, which only the re-derivation can produce.
if [ "$RUN_RC" -ne 0 ] && [ "$(commits "$W1")" -eq 2 ] \
   && grep -q 'not part-way through an adoption' "$RUN_OUT" "$RUN_ERR" 2>/dev/null; then
  pass "WIN4: --finish on an adoption that already landed is refused BY THE WINDOW CHECK — named, not merely by an empty commit failing"
else
  fail_ "WIN4" "rc=$RUN_RC commits=$(commits "$W1") (want 2) named-the-reason=$(grep -c 'not part-way through an adoption' "$RUN_OUT" "$RUN_ERR" 2>/dev/null | awk -F: '{s+=$1} END{print s+0}')"
fi

# WIN5 — --finish with the write set gone must REFUSE, never fall back to -A.
W5="$(newtmp)/p"; mkdir -p "$W5"; mk_window "$W5"
rm -f "$W5/$WS"
printf 'my own work\n' > "$W5/NOTES.txt"
run_in "$W5" --finish
w5_notes=0; git -C "$W5" ls-files --error-unmatch NOTES.txt >/dev/null 2>&1 && w5_notes=1
# Assert the guard's OWN message: without it the run reaches `git add` with an
# empty pathspec, git fails, and rc/count look identical to a working guard.
if [ "$RUN_RC" -ne 0 ] && [ "$(commits "$W5")" -eq 1 ] && [ "$w5_notes" -eq 0 ] \
   && grep -q 'record of what that adoption wrote is missing' "$RUN_OUT" "$RUN_ERR" 2>/dev/null; then
  pass "WIN5: with the write set absent --finish REFUSES, naming the missing record — it does not fall back to staging everything"
else
  fail_ "WIN5" "rc=$RUN_RC commits=$(commits "$W5") (want 1) notes-swept-in=$w5_notes (want 0) named-the-record=$(grep -c 'record of what that adoption wrote is missing' "$RUN_OUT" "$RUN_ERR" 2>/dev/null | awk -F: '{s+=$1} END{print s+0}')"
fi

# WIN6 — --finish on a project that was never adopted at all.
W6="$(newtmp)/p"; mkdir -p "$W6"; mk_adoptee "$W6"
run_in "$W6" --finish
if [ "$RUN_RC" -ne 0 ] && [ "$(commits "$W6")" -eq 1 ]; then
  pass "WIN6: --finish on a project that was never adopted is refused"
else
  fail_ "WIN6" "rc=$RUN_RC commits=$(commits "$W6") (want 1)"
fi

# WIN7 — a written path containing a SPACE. Adoption writes no such path today,
# and this repository's own directory name is a standing argument against
# resting on that: an unquoted `$(tr '\n' ' ' < "$ws")` word-splits, and the
# finish refuses with `fatal: pathspec 'a' did not match any files` — an
# adoption that could never be completed. Measured before the fix.
W7="$(newtmp)/p"; mkdir -p "$W7"; mk_window "$W7"
if [ -f "$W7/$WS" ]; then
  mkdir -p "$W7/.claude/adoption/with space" && printf 'x\n' > "$W7/.claude/adoption/with space/f.txt"
  printf '%s\n' ".claude/adoption/with space/f.txt" >> "$W7/$WS"
  rm -f "$W7/.git/hooks/pre-commit"
  run_in "$W7" --finish
  w7_tracked=0
  git -C "$W7" ls-files --error-unmatch ".claude/adoption/with space/f.txt" >/dev/null 2>&1 && w7_tracked=1
  if [ "$RUN_RC" -eq 0 ] && [ "$w7_tracked" -eq 1 ]; then
    pass "WIN7: a written path containing a space is staged and committed — the write set is read as lines, never word-split"
  else
    fail_ "WIN7" "rc=$RUN_RC space-path-tracked=$w7_tracked (want 1); $(grep -m1 'pathspec' "$RUN_OUT" "$RUN_ERR" 2>/dev/null | cut -c1-90)"
  fi
else
  fail_ "WIN7 setup" "the window fixture produced no write set"
fi

echo "=== REH — the rehearsal's bound and its cost (item 7) ==="

R1="$(newtmp)/p"; mkdir -p "$R1"; mk_adoptee "$R1"
run_in "$R1"
if [ "$RUN_RC" -eq 0 ] && grep -q 'rehearsal ran in' "$RUN_OUT" 2>/dev/null \
   && grep -q 'objects shared' "$RUN_OUT" 2>/dev/null; then
  pass "REH1: the transcript states what the rehearsal cost and that the object store was shared, not copied"
else
  fail_ "REH1" "rc=$RUN_RC says-cost=$(grep -c 'rehearsal ran in' "$RUN_OUT" 2>/dev/null) says-shared=$(grep -c 'objects shared' "$RUN_OUT" 2>/dev/null)"
fi

# REH2 — the copy really does share the object store rather than duplicating it.
R2="$(newtmp)/p"; mkdir -p "$R2"; mk_adoptee "$R2"
R2KEEP="$(newtmp)/keep"
RUN_RC=0; RUN_OUT="$TOPTMP/r2o"; RUN_ERR="$TOPTMP/r2e"; A="$TOPTMP/r2a"; _ans > "$A"
( cd "$R2" && SOIF_REHEARSAL_KEEP="$R2KEEP" bash "$DRIVER" --scan-report "$REPORT" ) < "$A" > "$RUN_OUT" 2> "$RUN_ERR" || RUN_RC=$?
r2_alt="$(find "$R2KEEP" -name alternates -path '*/objects/info/*' 2>/dev/null | head -1)"
# EVERY object entry, not just packs: a fresh fixture's objects are LOOSE, so
# "no pack of its own" is true of a full copy too and the assertion was vacuous
# against the copy-everything mutant. Count what is under .git/objects that is
# not the info/ directory the alternates file lives in.
r2_own=$(find "$R2KEEP" -path '*/.git/objects/*' -type f 2>/dev/null | grep -v '/objects/info/' | wc -l | tr -d ' ')
case "$r2_own" in ''|*[!0-9]*) r2_own=0 ;; esac
if [ -n "$r2_alt" ] && grep -q "$R2" "$r2_alt" 2>/dev/null \
   && [ "$r2_own" -eq 0 ]; then
  pass "REH2: the rehearsal copy carries .git/objects/info/alternates naming the project's own object store, and holds ZERO objects of its own ($r2_own)"
else
  fail_ "REH2" "alternates=${r2_alt:-ABSENT} names-project=$([ -n "$r2_alt" ] && grep -c "$R2" "$r2_alt" 2>/dev/null || echo 0) own-objects=$r2_own (want 0)"
fi

# REH3 — the bound refuses BEFORE copying, with the measured size in the message.
R3="$(newtmp)/p"; mkdir -p "$R3"; mk_adoptee "$R3"
RUN_RC=0; RUN_OUT="$TOPTMP/r3o"; RUN_ERR="$TOPTMP/r3e"; A3="$TOPTMP/r3a"; _ans > "$A3"
( cd "$R3" && SOIF_ADOPT_REHEARSAL_MAX_MB=0 bash "$DRIVER" --scan-report "$REPORT" ) < "$A3" > "$RUN_OUT" 2> "$RUN_ERR" || RUN_RC=$?
r3_wrote=0; [ -e "$R3/.claude" ] && r3_wrote=1
if [ "$RUN_RC" -ne 0 ] && [ "$r3_wrote" -eq 0 ] && [ "$(commits "$R3")" -eq 1 ] \
   && grep -qiE 'MB|rehearsal' "$RUN_OUT" "$RUN_ERR" 2>/dev/null; then
  pass "REH3: SOIF_ADOPT_REHEARSAL_MAX_MB=0 refuses before copying — nothing written, no commit, and the message names the size"
else
  fail_ "REH3" "rc=$RUN_RC wrote=$r3_wrote (want 0) commits=$(commits "$R3") named=$(grep -ciE 'MB|rehearsal' "$RUN_OUT" "$RUN_ERR" 2>/dev/null | awk -F: '{s+=$1} END{print s+0}')"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]

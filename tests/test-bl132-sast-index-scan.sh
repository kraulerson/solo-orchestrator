#!/usr/bin/env bash
# tests/test-bl132-sast-index-scan.sh — BL-132: the pre-commit SAST arm must scan
# the STAGED CONTENT (the bytes being committed), not the WORKTREE bytes.
#
# WHY THIS EXISTS (BL-118 adversarial verification, PR #199)
#   The armed pre-commit SAST arm handed semgrep the staged PATHNAMES
#   (`git diff --cached --name-only`), so semgrep read whatever was on DISK — which
#   need not be the staged bytes. Repro: `git add app.ts` (containing the XSS),
#   overwrite the worktree app.ts with a clean version, `git commit` -> the commit
#   LANDS with the `[OK]` receipt while `git show HEAD:app.ts` still holds the
#   vulnerable innerHTML. `git add -p` / stage-then-edit share the hole in the
#   benign direction (a false block on unstaged edits). The fix materializes the
#   staged blobs into a temp tree (# BL-132-INDEX-SCAN in scripts/lib/hook-
#   templates.sh) and points semgrep there, mapping finding paths back.
#
# CASES
#   T-index-blocks-staged-vuln    live — stage innerHTML XSS, overwrite the worktree
#                                 copy CLEAN, commit -> REFUSED (the STAGED bytes are
#                                 scanned), HEAD unmoved, [BLOCKED], and the real
#                                 path app.ts appears (temp-prefix mapping).
#                                 RED pre-fix: commit LANDS with [OK].
#   T-index-no-false-block        live — stage CLEAN, overwrite the worktree copy
#                                 with the vuln, commit -> LANDS (the unstaged vuln
#                                 is not the committed bytes; no false block).
#   T-notrun-contract-intact      live — semgrep shimmed OFF the PATH -> the commit
#                                 LANDS and the operator is told LOUDLY that SAST did
#                                 not run ([WARN] semgrep not found + SAST NOT
#                                 ENFORCED). The refactor must not disturb the
#                                 # BL-112-SAST-NOTRUN contract.
#   T-index-gitlink-not-blinding  live — a staged SUBMODULE GITLINK alongside a staged
#                                 vuln must NOT blind the scan. RED pre-fix: index
#                                 mode 160000 is not a blob, `git cat-file blob :sub`
#                                 exits 128, the loop `break` discarded EVERY already-
#                                 materialized target and the whole commit went NOTRUN
#                                 -> the sibling vuln LANDED (# BL-132-GITLINK-SKIP).
#   T-index-gitlink-only-honest   live — a submodule POINTER-BUMP commit (only a
#                                 gitlink staged, nothing scannable) LANDS but must
#                                 NOT print an `[OK] semgrep: SAST ran` receipt it did
#                                 not earn — 0 materialized targets => loud NOTRUN.
#   T-index-case-collision        live — BL-178: two staged paths differing only in
#                                 case collide in a single flat temp tree on a case-
#                                 INSENSITIVE filesystem; the later (clean) write
#                                 clobbers the earlier (vuln) blob and the vuln lands
#                                 with a false [OK]. Per-index subdirs
#                                 (# BL-178-PER-INDEX-DIR) make the collision
#                                 impossible. LOUD-SKIPs on a case-sensitive FS
#                                 (unobservable there, would pass vacuously).
#   T-index-stage-syntax-path     live — R-270-1B: a repo-ROOT staged path named
#                                 `0:`..`3:`<something> collides with git's
#                                 `:<stage>:<path>` MERGE-STAGE revision syntax, so the
#                                 bare `git cat-file -t ":$soif_p"` fails on a HEALTHY
#                                 blob; it is no gitlink, so it fell through to the
#                                 then-existing `soif_idx_ok=0; break` (retired by
#                                 # BL-182-PER-ENTRY-SKIP) and the WHOLE commit went
#                                 NOTRUN while a vulnerable sibling LANDED. The stage-0
#                                 prefix (# BL-132-STAGE0-REF) disambiguates; after
#                                 BL-182 the same entry would instead forfeit the
#                                 commit's [OK] receipt, so the prefix still earns it.
#                                 RED pre-fix: COMMITTED + "could not materialize".
#   T-rename-edit-scanned         live — BL-179: `diff.renames` defaults TRUE, so a
#                                 rename-AND-edit commit is one status-R entry, which
#                                 `--diff-filter=ACM` EXCLUDED. soif_staged came back
#                                 empty and the arm (a `-gt 0` wrapper with no `else`)
#                                 was skipped IN SILENCE. Filter -> ACMR. RED pre-fix:
#                                 COMMITTED with ZERO SAST lines in the log.
#   T-rename-only-not-silent      live — the residual R100 shape: a content-free rename
#                                 must LAND but still be RECEIPTED. Pins the SILENCE.
#   T-delete-only-honest          live — D stays OUT of the filter (do NOT copy the
#                                 BL-125 arm's ACMDR): a deleted path has no staged
#                                 blob, so including it would manufacture an unreadable
#                                 entry. Deletion-only must land, be receipted, and
#                                 never reach the loop with a blob-less entry.
#   T-typechange-scanned          live — R-WPC-1: a staged TYPE CHANGE (status letter T,
#                                 e.g. a symlink materialized into a regular file) is a
#                                 real blob with real content, and `--diff-filter=ACMR`
#                                 EXCLUDED it. A clean sibling kept soif_staged non-empty,
#                                 so the commit never reached the empty-staged report and
#                                 instead printed `[OK] … on 1 staged file(s)` over TWO
#                                 staged blobs. Filter -> ACMRT. RED pre-fix: COMMITTED
#                                 with that unearned receipt and the sink in HEAD.
#   T-partial-clean-no-receipt    live — BL-182: one staged entry cannot be
#                                 materialized, every other scans CLEAN. That is NOT a
#                                 clean commit: NO [OK] receipt, loud NOTRUN, and the
#                                 unreadable entry NAMED. RED pre-fix: the whole-commit
#                                 abort names nothing and leaks a raw tool diagnostic.
#   T-partial-vuln-still-blocks   live — BL-182, the regression the all-or-nothing
#                                 `break` actually caused: one unreadable entry
#                                 DISCARDED every materialized sibling, so a sibling's
#                                 sink LANDED. A partial scan that finds a vuln must
#                                 still [BLOCKED].
#   T-gitlink-not-counted-unread  live — the two per-entry `continue`s mean OPPOSITE
#                                 things: a gitlink is skipped with NO trace (not
#                                 content), an unreadable entry forfeits the whole
#                                 commit's [OK] and is named. Pins the ACCEPT direction
#                                 of the mode predicate; the REJECT direction is the
#                                 case below (its unreadable entry is a HEALTHY blob
#                                 that fails at the WRITE site, so it never enters the
#                                 non-blob branch at all).
#   T-nonblob-nongitlink-forfeits-receipt
#                                 live — R-WPC2-1: a staged entry that is neither a blob
#                                 nor a gitlink (a TREE object staged at index mode
#                                 100644) must forfeit the receipt and be NAMED. Pins
#                                 the REJECT direction of # BL-132-GITLINK-SKIP's mode
#                                 test. RED under a widened predicate: [OK] receipt over
#                                 a commit landing with an unscanned staged entry.
#   T-pathmax-sibling-caught      live — BL-182's original trigger: a repo-relative path
#                                 that overflows PATH_MAX under the mktemp temp root.
#                                 Fires at the dirname/mkdir recovery point (the
#                                 LONG_NAME cases fire at the write point). LOUD-SKIPs
#                                 where the host can express the path.
#   T-mutation-rename-filter      live — proof (a): ACMRT -> ACMT -> the rename case
#                                 LANDS its XSS (RED) -> restore -> REFUSED (GREEN).
#   T-mutation-typechange-filter  live — ACMRT -> ACMR (the pre-R-WPC-1 value) -> the
#                                 type-change case LANDS its sink behind an UNEARNED [OK]
#                                 receipt (RED) -> restore -> REFUSED (GREEN).
#   T-mutation-delete-filter      live — ACMRT -> ACMDRT -> a deletion-only commit reports
#                                 lost coverage on a phantom entry (RED) -> restore ->
#                                 honest receipt, no phantom (GREEN).
#   T-mutation-empty-staged-silence  neuter the empty-staged report -> a deletion-only
#                                 commit goes TOTALLY SILENT again (RED) -> restore ->
#                                 receipted (GREEN). Pins the second half of BL-179.
#                                 Needs no semgrep — an empty target set never reaches
#                                 the scanner.
#   T-mutation-partial-break      live — proof (b): restore the all-or-nothing recovery
#                                 -> the partial+vuln case LANDS the sibling XSS (RED)
#                                 -> restore per-entry recovery -> REFUSED (GREEN).
#   T-mutation-partial-receipt    live — proof (c): disarm the no-unearned-receipt guard
#                                 -> a clean-but-partial scan prints [OK] (RED) ->
#                                 restore -> loud partial NOTRUN (GREEN).
#   T-mutation-gitlink-mode-blanket  live — R-WPC2-1: widen the skip's MODE test
#                                 (`^160000 ` -> `^`) into the blanket "unreadable =>
#                                 skip" the code forbids -> an unscanned staged entry
#                                 LANDS behind an [OK] receipt (RED) -> restore ->
#                                 receipt forfeited and the entry named (GREEN).
#   T-oversize-blob-scanned       live — R-274R-1: a staged blob over semgrep's DEFAULT
#                                 --max-target-bytes (1,000,000) is dropped by the
#                                 SCANNER with no error and rc=0, so it never reaches a
#                                 rule while the arm still prints `[OK] … ran on N staged
#                                 file(s)` — the first member of this arm's silent-success
#                                 class to emit a POSITIVE FALSE ATTESTATION. Same content,
#                                 only padding differs: 900,037 bytes -> REFUSED,
#                                 1,100,032 -> COMMITTED with [OK]. Fixed at
#                                 # BL-112-MAX-TARGET-BYTES (=0 disables the filter).
#                                 RED pre-fix: COMMITTED, [OK] receipt, sink in HEAD.
#   T-coverage-parse-fails-closed live — # BL-112-SCAN-COVERAGE must FAIL CLOSED. Break
#                                 the scan-status parse (as a semgrep output redesign
#                                 would) and a fully-covered CLEAN commit must take the
#                                 loud NOTRUN, never [OK]. Pins that the parser itself
#                                 cannot become a silent-success path.
#   T-mutation-max-target-bytes   live — proof (a): strip the --max-target-bytes=0 line ->
#                                 the oversize sink is never scanned and the commit LANDS
#                                 (RED) -> restore -> REFUSED + [BLOCKED] (GREEN). Also
#                                 asserts the RED transcript carries NO [OK]: with the
#                                 flag gone the coverage guard must still hold the honesty
#                                 line even though the sink escapes.
#   T-mutation-scan-coverage      live — proof (b), the CLASS guard in isolation: with the
#                                 flag already stripped, neuter # BL-112-SCAN-COVERAGE
#                                 (soif_sg_covered=0 -> =1) -> the unscanned oversize blob
#                                 buys an [OK] receipt and LANDS (RED) -> restore the guard
#                                 alone -> no [OK], loud coverage NOTRUN naming the staged
#                                 entries (GREEN). This is what proves the fix is the class
#                                 and not the flag.
#   T-mutation-index-scan         live — revert the emitted hook's scan target to the
#                                 worktree paths (the pre-BL-132 behaviour) ->
#                                 T-index-blocks-staged-vuln goes RED (the clean
#                                 worktree scans clean, vuln commits) -> restore ->
#                                 GREEN. Proves the index snapshot is load-bearing.
#
#   The live cases talk to the semgrep registry (owasp/browser config fetch). A host
#   where that fails yields LOUD SKIPs, never silent passes. The blocking vuln here
#   (innerHTML) is caught by the registry browser pack, so this suite exercises the
#   index-scan PLUMBING independently of the BL-131 custom ruleset — but the emitted
#   hook references that ruleset, so the fixture ships it (.semgrep/soif-dom-sinks.yml).
#
# REGISTRATION: never runs init.sh, not an aggregator -> registered in BOTH
# tests/full-project-test-suite.sh AND the tests.yml unit fast lane.
# Hermetic: mktemp workdirs, local git identity, GITHUB_BASE_REF unset, no remote.
# bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

unset GITHUB_BASE_REF 2>/dev/null || true

PASSED=0
FAILED=0
SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip_() { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

HOOK_SRC="$REPO_ROOT/scripts/lib/hook-templates.sh"
RULESET_SRC="$REPO_ROOT/templates/semgrep/soif-dom-sinks.yml"
EMITTED="$TOPTMP/emitted-hook"

if [ ! -f "$HOOK_SRC" ]; then
  echo "SKIP: scripts/lib/hook-templates.sh missing"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi
# shellcheck source=/dev/null
. "$HOOK_SRC"
soif_write_precommit_hook "$EMITTED"

# ── The semgrep predicate, stated LOUDLY (a silent security skip is the BL-112 lie) ─
HAVE_SEMGREP=0
if command -v semgrep >/dev/null 2>&1; then
  HAVE_SEMGREP=1
else
  echo ""
  echo "#################################################################"
  echo "## semgrep IS NOT INSTALLED ON THIS HOST.                      ##"
  echo "## The index-scan live cases are SKIPPED, NOT PASSED.          ##"
  echo "## Install semgrep to exercise them: brew install semgrep      ##"
  echo "#################################################################"
  echo ""
fi

XSS_TS='export function render(pane: HTMLElement, userText: string) {
  pane.innerHTML = userText;
}'
SAFE_TS='export function render(pane: HTMLElement, userText: string) {
  pane.textContent = userText;
}'
# A DOM-sink caught by the LOCAL ruleset (soif-insert-adjacent-html), valid as both
# .ts and .js so it can be staged under .min.js. Used by the ignored-paths regression.
IA_SINK='function render(el, u) {
  el.insertAdjacentHTML("beforeend", u);
}'

# ── R-274R-1 oversize fixture ────────────────────────────────────────────────
# write_oversize <dest> <first-lines>: <first-lines> followed by enough comment padding
# to carry the file PAST semgrep's documented default --max-target-bytes (1,000,000).
# The sink sits on line 2 — "large" is not "safe", and the point of the case is that a
# perfectly ordinary vulnerability rides in on a file that merely got big (a generated
# bundle, a vendored lib, a fixture corpus). Padding is emitted by awk, not a bash loop:
# a 1MB file built one `echo` at a time is measurably slow in bash 3.2 and this suite
# builds several.
OVERSIZE_MIN=1000000
write_oversize() {
  { printf '%s\n' "$2"
    awk 'BEGIN{ l="// "; for(i=0;i<25;i++) l = l "padding"; for(n=0;n<7000;n++) print l }'
  } > "$1"
}
# is_oversize <file>: TRUE iff the file really cleared the limit on THIS host. Every
# case that depends on the shape re-probes it and LOUD-SKIPs rather than passing
# vacuously — the same discipline the rename fixtures use for `--name-status`.
is_oversize() {
  local n
  n=$(wc -c < "$1" 2>/dev/null | tr -d '[:space:]') || n=0
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  [ "$n" -gt "$OVERSIZE_MIN" ]
}

# ── BL-179 rename fixtures ───────────────────────────────────────────────────
# git only reports a RENAME (status R) when the destination is similar enough to the
# source; below the threshold it reports A + D instead — and A is in ACM, so the
# defect does not even trigger. VERIFIED on this host (git 2.50.1): a 3-line file
# flipping textContent -> innerHTML scored `A new.ts / D old.ts`, NOT R. These
# fixtures carry padding so a single-line edit keeps similarity high and the staged
# status really is R. Every case that depends on it re-probes `--name-status` and
# LOUD-SKIPs when git disagrees, rather than passing vacuously.
REN_SAFE='export function render(pane: HTMLElement, userText: string) {
  const a1 = 1; const a2 = 2; const a3 = 3; const a4 = 4;
  const a5 = 5; const a6 = 6; const a7 = 7; const a8 = 8;
  const a9 = 9; const b1 = 10; const b2 = 11; const b3 = 12;
  const b4 = 13; const b5 = 14; const b6 = 15; const b7 = 16;
  pane.textContent = userText;
}'
REN_VULN='export function render(pane: HTMLElement, userText: string) {
  const a1 = 1; const a2 = 2; const a3 = 3; const a4 = 4;
  const a5 = 5; const a6 = 6; const a7 = 7; const a8 = 8;
  const a9 = 9; const b1 = 10; const b2 = 11; const b3 = 12;
  const b4 = 13; const b5 = 14; const b6 = 15; const b7 = 16;
  pane.innerHTML = userText;
}'

# ── BL-182 unreadable-entry generators ───────────────────────────────────────
# Two staged entries that the INDEX can hold but the FILESYSTEM cannot express as a
# materialization destination — the shape that used to abort the whole loop:
#   LONG_NAME  a 303-byte single path COMPONENT. Every POSIX filesystem caps a
#              component at NAME_MAX (255), so the `git cat-file blob > $dest`
#              REDIRECT fails with ENAMETOOLONG regardless of how short the temp root
#              is. Host-independent, which is why it is the primary generator here.
#   LONG_PATH  a 1015-byte repo-relative path — the ORIGINAL BL-182 trigger. Whether
#              it overflows depends on the mktemp root length vs PATH_MAX, so its case
#              probes the host and LOUD-SKIPs if this host can represent it.
LONG_NAME=""
_bl182_i=0
while [ "$_bl182_i" -lt 30 ]; do LONG_NAME="${LONG_NAME}0123456789"; _bl182_i=$((_bl182_i + 1)); done
LONG_NAME="${LONG_NAME}.ts"
LONG_PATH=""
_bl182_i=0
while [ "$_bl182_i" -lt 24 ]; do LONG_PATH="${LONG_PATH}d0123456789012345678901234567890123456789/"; _bl182_i=$((_bl182_i + 1)); done
LONG_PATH="${LONG_PATH}long.js"

# mk_repo <dir> <hookfile>: fresh repo w/ local identity + one benign commit landed
# BEFORE the hook is installed, then the given hook installed as pre-commit and the
# BL-131 ruleset placed at .semgrep/ (the emitted hook references it by --config).
mk_repo() {
  local d="$1" hook="$2"
  mkdir -p "$d/.semgrep"
  ( cd "$d" \
      && git init -q \
      && git config user.email "bl132@test.invalid" \
      && git config user.name  "BL-132 Test" \
      && echo "# bl132" > README.md \
      && git add README.md \
      && git commit -q -m "chore: init" ) || return 1
  [ -f "$RULESET_SRC" ] && cp "$RULESET_SRC" "$d/.semgrep/soif-dom-sinks.yml"
  cp "$hook" "$d/.git/hooks/pre-commit"
  chmod +x "$d/.git/hooks/pre-commit"
}

head_of() { ( cd "$1" && git rev-parse HEAD 2>/dev/null ) || echo none; }
not_enforced() { grep -q "SAST NOT ENFORCED" "$1"; }

# mk_repo_seeded <dir> <hookfile> <seedpath> <seedcontent>: mk_repo, then land ONE
# more commit carrying <seedpath> BEFORE the hook is armed — so the seed does not pay
# for a semgrep run and cannot be blocked. Needed by every rename/deletion fixture:
# a rename has to have something to rename FROM.
mk_repo_seeded() {
  local d="$1" hook="$2" sp="$3" sc="$4"
  mk_repo "$d" "$hook" || return 1
  rm -f "$d/.git/hooks/pre-commit"
  printf '%s\n' "$sc" > "$d/$sp"
  ( cd "$d" && git add -- "$sp" && git commit -q -m "chore: seed $sp" ) || return 1
  cp "$hook" "$d/.git/hooks/pre-commit"
  chmod +x "$d/.git/hooks/pre-commit"
}

# mk_repo_typechange <dir> <hookfile>: mk_repo, then land a SYMLINK (link.ts -> README.md)
# plus a clean regular sibling (app.ts) BEFORE the hook is armed, then arm it. The caller
# replaces link.ts with a REGULAR FILE, which git reports as a status-T TYPE CHANGE.
# Returns non-zero when this host cannot produce the shape — no symlink support, or
# core.symlinks=false storing the seed as a plain blob — so the case LOUD-SKIPs instead
# of quietly degrading into an ordinary `M` that proves nothing about the T filter.
mk_repo_typechange() {
  local d="$1" hook="$2"
  mk_repo "$d" "$hook" || return 1
  rm -f "$d/.git/hooks/pre-commit"
  ( cd "$d" && ln -s README.md link.ts ) 2>/dev/null || return 1
  [ -L "$d/link.ts" ] || return 1
  printf '%s\n' 'export const seeded = 1;' > "$d/app.ts"
  ( cd "$d" && git add -- link.ts app.ts && git commit -q -m "chore: seed symlink + sibling" ) || return 1
  # The seeded INDEX entry must really be mode 120000. On a checkout where git stored
  # the symlink as a regular file the later replacement is an `M`, not a `T`.
  ( cd "$d" && git ls-files -s -- ":(literal)link.ts" 2>/dev/null ) | grep -q '^120000 ' || return 1
  cp "$hook" "$d/.git/hooks/pre-commit"
  chmod +x "$d/.git/hooks/pre-commit"
}

# any_sast_line <log>: TRUE iff the SAST arm said ANYTHING AT ALL.
#   THIS IS THE BL-179 ASSERTION AND IT IS DELIBERATELY SHAPED AS THE ABSENCE OF AN
#   ABSENCE. The rename-and-edit defect is SILENCE — soif_staged came back empty and
#   the arm was wrapped in a `-gt 0` test with no `else`, so there was no [OK], no
#   [BLOCKED], and not even the loud NOTRUN. A `! grep [BLOCKED]` assertion PASSES
#   VACUOUSLY on that: "no [BLOCKED]" is exactly what total silence looks like. Only
#   an assertion that some verdict WAS printed can tell a scan that cleared the commit
#   apart from a scanner that was never asked.
any_sast_line() { grep -qE '\[OK\] semgrep: SAST ran|\[BLOCKED\] Semgrep|SAST NOT ENFORCED' "$1"; }

# stage_index_only <repo> <path> <content>: hash <content> into the object store and
# add it to the INDEX at <path> WITHOUT ever creating a worktree file. The BL-182
# entries cannot exist on disk (a 303-byte name component, a 1015-byte path), but the
# index holds them happily — which is the whole defect: legal in the index, and the
# materialization destination is what overflows.
stage_index_only() {
  local d="$1" p="$2" c="$3" sha
  sha="$( printf '%s\n' "$c" | ( cd "$d" && git hash-object -w --stdin ) )" || return 1
  [ -n "$sha" ] || return 1
  ( cd "$d" && git update-index --add --cacheinfo "100644,$sha,$p" ) >/dev/null 2>&1
}

# stage_tree_at_blob_mode <repo> <path>: write a real TREE object into <repo>'s object
# store and add it to the INDEX at <path> CLAIMING index mode 100644. The result is a
# staged entry that `git ls-files -s` reports as a blob (`100644 <sha> 0 <path>`) while
# `git cat-file -t :0:<path>` resolves to `tree` — i.e. NOT a blob and NOT a gitlink.
#   THIS IS THE REJECT DIRECTION OF THE # BL-132-GITLINK-SKIP MODE PREDICATE, and it is
#   the only generator in this suite that reaches it. Every other unreadable-entry
#   generator here (LONG_NAME, LONG_PATH) stages a HEALTHY blob and fails LATER, at the
#   dirname/mkdir or write site, so the non-blob branch is never entered at all and the
#   mode test is invisible to them. `--cacheinfo` is the only way to build the shape:
#   git will not produce a mode/type mismatch on its own, which is exactly why it is a
#   fixture and not a repo state anyone reaches by accident.
# Hermetic: the tree is built through a THROWAWAY index (GIT_INDEX_FILE) so the repo's
# real index is untouched, and the scratch worktree dir is removed again — no remote,
# no submodule, nothing outside the fixture repo.
stage_tree_at_blob_mode() {
  local d="$1" p="$2" tsha
  mkdir -p "$d/.bl182src" || return 1
  printf 'x\n' > "$d/.bl182src/inner.txt" || return 1
  tsha="$( cd "$d" \
             && GIT_INDEX_FILE="$d/.git/bl182-scratch-index" git add -- .bl182src/inner.txt >/dev/null 2>&1 \
             && GIT_INDEX_FILE="$d/.git/bl182-scratch-index" git write-tree 2>/dev/null )" || tsha=""
  rm -f "$d/.git/bl182-scratch-index"
  rm -rf "$d/.bl182src"
  [ -n "$tsha" ] || return 1
  [ "$( cd "$d" && git cat-file -t "$tsha" 2>/dev/null )" = "tree" ] || return 1
  ( cd "$d" && git update-index --add --cacheinfo "100644,$tsha,$p" ) >/dev/null 2>&1
}

# fs_can_hold_name <name>: TRUE iff this filesystem accepts <name> as a single path
# component. The LONG_NAME generator only proves anything where it FAILS.
fs_can_hold_name() {
  local probe="$TOPTMP/nameprobe"
  rm -rf "$probe"; mkdir -p "$probe" || return 0
  ( : > "$probe/$1" ) 2>/dev/null || { rm -rf "$probe"; return 1; }
  rm -rf "$probe"; return 0
}

# _del_commit <hookfile> <log> -> COMMITTED|REFUSED|SETUPFAIL: land a clean file, then
# commit its PURE DELETION through <hookfile>. Shared by the two mutation cases that
# attack the deletion/empty-staged shapes; needs no semgrep, because a deletion-only
# commit has no content for the scanner to look at — which is the entire point.
_del_commit() {
  local d; d="$(mktemp -d)"
  mk_repo_seeded "$d" "$1" gone.ts "$REN_SAFE" >/dev/null 2>&1 || { rm -rf "$d"; echo SETUPFAIL; return; }
  ( cd "$d" && git rm -q gone.ts ) >/dev/null 2>&1
  if ( cd "$d" && git commit -m "chore: drop dead module" ) >"$2" 2>&1; then echo COMMITTED; else echo REFUSED; fi
  rm -rf "$d"
}

# temp_tree_can_hold_path <relpath>: TRUE iff a mktemp -d root + the BL-178 per-index
# segment + <relpath> is expressible on this host. The PATH_MAX case only proves
# anything where it is NOT.
temp_tree_can_hold_path() {
  local t rc=0
  t="$(mktemp -d)" || return 0
  mkdir -p "$( dirname "$t/1/$1" 2>/dev/null )" 2>/dev/null || rc=1
  rm -rf "$t"
  [ "$rc" -eq 0 ]
}

# stage_then_overwrite <repo> <staged-content> <worktree-content> <log>
#   Stage app.ts with <staged-content>, then overwrite the worktree copy with
#   <worktree-content> WITHOUT re-staging, then attempt the commit. Echoes
#   COMMITTED|REFUSED, git rc in the log.
stage_then_overwrite() {
  local d="$1" staged="$2" worktree="$3" log="$4"
  printf '%s\n' "$staged"   > "$d/app.ts"
  ( cd "$d" && git add app.ts )
  printf '%s\n' "$worktree" > "$d/app.ts"     # worktree now DIVERGES from the index
  if ( cd "$d" && git commit -m "feat: app" ) >"$log" 2>&1; then echo "COMMITTED"; else echo "REFUSED"; fi
}

# ── T-index-blocks-staged-vuln ───────────────────────────────────────────────
echo "=== T-index-blocks-staged-vuln ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-index-blocks-staged-vuln" "semgrep ABSENT — index-scan blocking UNPROVEN (skip, not pass)"
else
  R1="$TOPTMP/blk"
  if ! mk_repo "$R1" "$EMITTED"; then
    fail_ "T-index-blocks-staged-vuln" "repo setup failed"
  else
    H0="$(head_of "$R1")"
    V="$(stage_then_overwrite "$R1" "$XSS_TS" "$SAFE_TS" "$TOPTMP/o1")"
    H1="$(head_of "$R1")"
    if [ "$V" = "COMMITTED" ]; then
      if not_enforced "$TOPTMP/o1"; then
        skip_ "T-index-blocks-staged-vuln" "scanner did not run (registry unreachable?) — blocking UNPROVEN here"
      else
        fail_ "T-index-blocks-staged-vuln" "staged innerHTML XSS COMMITTED CLEAN — the WORKTREE (clean) was scanned, not the index (BL-132): $(grep -E '\[OK\]|\[BLOCKED\]' "$TOPTMP/o1" | head -1)"
      fi
    elif ! grep -q "\[BLOCKED\]" "$TOPTMP/o1"; then
      fail_ "T-index-blocks-staged-vuln" "refused but without [BLOCKED] (wrong reason): $(tail -3 "$TOPTMP/o1" | tr '\n' '|')"
    elif [ "$H0" != "$H1" ]; then
      fail_ "T-index-blocks-staged-vuln" "non-zero exit but HEAD MOVED"
    elif ! grep -q "app.ts" "$TOPTMP/o1"; then
      fail_ "T-index-blocks-staged-vuln" "blocked, but the finding did not name the real path app.ts — temp-prefix mapping missing"
    elif grep -qE '/var/folders/|/tmp/tmp\.' "$TOPTMP/o1"; then
      fail_ "T-index-blocks-staged-vuln" "the raw mktemp temp-tree prefix leaked into the operator-facing output — the path-mapping sed did not run (F3); a bare 'app.ts' grep passes anyway because the temp path contains the basename"
    else
      pass "T-index-blocks-staged-vuln: STAGED bytes scanned, commit refused, HEAD unmoved, real repo-relative path shown (no temp prefix)"
    fi
  fi
fi

# ── T-index-no-false-block ───────────────────────────────────────────────────
echo "=== T-index-no-false-block ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-index-no-false-block" "semgrep ABSENT — skip, not pass"
else
  R2="$TOPTMP/nofalse"
  if ! mk_repo "$R2" "$EMITTED"; then
    fail_ "T-index-no-false-block" "repo setup failed"
  else
    H0="$(head_of "$R2")"
    V="$(stage_then_overwrite "$R2" "$SAFE_TS" "$XSS_TS" "$TOPTMP/o2")"
    H1="$(head_of "$R2")"
    if not_enforced "$TOPTMP/o2"; then
      skip_ "T-index-no-false-block" "scanner did not run — case vacuous here"
    elif [ "$V" = "REFUSED" ]; then
      fail_ "T-index-no-false-block" "CLEAN staged content was BLOCKED because the hook scanned the UNSTAGED worktree vuln (false block): $(grep -E '\[BLOCKED\]' "$TOPTMP/o2" | head -1)"
    elif [ "$H0" = "$H1" ]; then
      fail_ "T-index-no-false-block" "committed verdict but HEAD did not move"
    elif ! grep -q "\[OK\] semgrep: SAST ran" "$TOPTMP/o2"; then
      fail_ "T-index-no-false-block" "landed but no [OK] receipt — cannot prove the scan RAN on the clean staged bytes"
    else
      pass "T-index-no-false-block: unstaged worktree vuln ignored, clean staged bytes scanned + landed"
    fi
  fi
fi

# ── T-notrun-contract-intact (semgrep OFF the PATH) ──────────────────────────
# Mirror bl112's honest shim: replace every PATH entry holding semgrep with a
# symlink mirror of all its OTHER entries, so semgrep — and only semgrep — is gone.
echo "=== T-notrun-contract-intact ==="
NOSEMGREP_PATH=""
build_nosemgrep_path() {
  local mirrors="$TOPTMP/nosemgrep" n=0 d np="" entry base
  rm -rf "$mirrors"; mkdir -p "$mirrors"
  printf '%s' "$PATH" | tr ':' '\n' > "$mirrors/.pathlist"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    if [ -x "$d/semgrep" ]; then
      n=$((n + 1)); mkdir -p "$mirrors/$n"
      for entry in "$d"/*; do
        [ -e "$entry" ] || continue
        base="${entry##*/}"
        [ "$base" = "semgrep" ] && continue
        ln -sf "$entry" "$mirrors/$n/$base" 2>/dev/null || true
      done
      np="${np:+$np:}$mirrors/$n"
    else
      np="${np:+$np:}$d"
    fi
  done < "$mirrors/.pathlist"
  NOSEMGREP_PATH="$np"
}
build_nosemgrep_path
if PATH="$NOSEMGREP_PATH" command -v semgrep >/dev/null 2>&1; then
  fail_ "T-notrun-contract-intact" "PATH shim failed — semgrep still resolves; contract UNPROVEN"
elif ! PATH="$NOSEMGREP_PATH" command -v git >/dev/null 2>&1; then
  fail_ "T-notrun-contract-intact" "PATH shim removed git too — would prove nothing"
else
  R3="$TOPTMP/notrun"
  if ! mk_repo "$R3" "$EMITTED"; then
    fail_ "T-notrun-contract-intact" "repo setup failed"
  else
    H0="$(head_of "$R3")"
    printf '%s\n' "$XSS_TS" > "$R3/app.ts"
    ( cd "$R3" && git add app.ts )
    if ( cd "$R3" && PATH="$NOSEMGREP_PATH" git commit -m "feat: app (no semgrep)" ) >"$TOPTMP/o3" 2>&1; then V=COMMITTED; else V=REFUSED; fi
    H1="$(head_of "$R3")"
    if [ "$V" = "COMMITTED" ] && [ "$H0" != "$H1" ] \
       && grep -qF '[WARN] semgrep not found' "$TOPTMP/o3" \
       && grep -qF 'SAST NOT ENFORCED' "$TOPTMP/o3" \
       && ! grep -qF '[BLOCKED]' "$TOPTMP/o3"; then
      pass "T-notrun-contract-intact: semgrep absent -> commit LANDS, SAST NOT ENFORCED shown, never blocked"
    else
      fail_ "T-notrun-contract-intact" "verdict=$V warn=$(grep -cF '[WARN] semgrep not found' "$TOPTMP/o3") loud=$(grep -cF 'SAST NOT ENFORCED' "$TOPTMP/o3") blocked=$(grep -cF '[BLOCKED]' "$TOPTMP/o3"); log: $(tail -4 "$TOPTMP/o3" | tr '\n' '|')"
    fi
  fi
fi

# ── T-index-ignored-paths-scanned (verifier F1 regression) ───────────────────
# Staged sinks under semgrep's default-ignored paths (tests/ dist/ *.min.js) MUST be
# scanned. Pointing semgrep at the materialized DIRECTORY re-engaged its built-in
# .semgrepignore and silently skipped them (F1); FIX B (explicit file targets)
# restores coverage. RED (pre-FIX-B, directory scan): these COMMIT with [OK].
echo "=== T-index-ignored-paths-scanned ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-index-ignored-paths-scanned" "semgrep ABSENT — skip, not pass"
else
  R4="$TOPTMP/ignored"
  if ! mk_repo "$R4" "$EMITTED"; then
    fail_ "T-index-ignored-paths-scanned" "repo setup failed"
  else
    mkdir -p "$R4/tests" "$R4/dist"
    printf '%s\n' "$IA_SINK" > "$R4/tests/vuln.ts"
    printf '%s\n' "$IA_SINK" > "$R4/dist/payload.ts"
    printf '%s\n' "$IA_SINK" > "$R4/lib.min.js"
    H0="$(head_of "$R4")"
    if ( cd "$R4" && git add tests/vuln.ts dist/payload.ts lib.min.js && git commit -m "feat: ignored-path sinks" ) >"$TOPTMP/o4" 2>&1; then V=COMMITTED; else V=REFUSED; fi
    H1="$(head_of "$R4")"
    if [ "$V" = "COMMITTED" ]; then
      if not_enforced "$TOPTMP/o4"; then
        skip_ "T-index-ignored-paths-scanned" "scanner did not run (registry unreachable?) — coverage UNPROVEN here"
      else
        fail_ "T-index-ignored-paths-scanned" "sinks under tests/ dist/ *.min.js COMMITTED CLEAN — default .semgrepignore silently skipped them (verifier F1 regression): $(grep -E '\[OK\]|\[BLOCKED\]' "$TOPTMP/o4" | head -1)"
      fi
    elif ! grep -q "\[BLOCKED\]" "$TOPTMP/o4"; then
      fail_ "T-index-ignored-paths-scanned" "refused but without [BLOCKED] (wrong reason): $(tail -3 "$TOPTMP/o4" | tr '\n' '|')"
    elif [ "$H0" != "$H1" ]; then
      fail_ "T-index-ignored-paths-scanned" "non-zero exit but HEAD MOVED"
    elif ! grep -q 'tests/vuln.ts' "$TOPTMP/o4" || ! grep -q 'dist/payload.ts' "$TOPTMP/o4" || ! grep -q 'lib.min.js' "$TOPTMP/o4"; then
      fail_ "T-index-ignored-paths-scanned" "blocked, but not all three ignored-path sinks were NAMED — one was still skipped (found $(grep -cE 'tests/vuln\.ts|dist/payload\.ts|lib\.min\.js' "$TOPTMP/o4") of 3 refs)"
    elif grep -qE '/var/folders/|/tmp/tmp\.' "$TOPTMP/o4"; then
      fail_ "T-index-ignored-paths-scanned" "raw mktemp temp-tree prefix leaked into output (F3)"
    else
      pass "T-index-ignored-paths-scanned: sinks under tests/ dist/ *.min.js are ALL scanned + REFUSED (F1 regression closed)"
    fi
  fi
  # control: a src/ sink is REFUSED both before and after FIX B — anchors that the
  # hook DOES block when it sees a sink (so the ignored-path RED is meaningful).
  R4c="$TOPTMP/ignored-ctrl"
  if mk_repo "$R4c" "$EMITTED"; then
    mkdir -p "$R4c/src"
    printf '%s\n' "$IA_SINK" > "$R4c/src/ctrl.ts"
    if ( cd "$R4c" && git add src/ctrl.ts && git commit -m "feat: src sink" ) >"$TOPTMP/o4c" 2>&1; then Vc=COMMITTED; else Vc=REFUSED; fi
    if not_enforced "$TOPTMP/o4c"; then
      skip_ "T-index-ignored-paths-control" "scanner did not run — control vacuous here"
    elif [ "$Vc" = "REFUSED" ] && grep -q "\[BLOCKED\]" "$TOPTMP/o4c"; then
      pass "T-index-ignored-paths-control: a src/ sink is REFUSED (the hook blocks when it sees a sink)"
    else
      fail_ "T-index-ignored-paths-control" "src/ sink verdict=$Vc (want REFUSED): $(tail -3 "$TOPTMP/o4c" | tr '\n' '|')"
    fi
  fi
fi

# ── T-index-gitlink-not-blinding (R-270-1 regression) ────────────────────────
# A staged SUBMODULE GITLINK is index mode 160000, NOT a blob: `git cat-file blob
# :sub` exits 128. The first cut's `|| { soif_idx_ok=0; break; }` (long since retired
# by # BL-182-PER-ENTRY-SKIP — quoted here as history, not as a code citation) threw
# away EVERY already-materialized target and routed the WHOLE commit to NOTRUN, so
# a vulnerability staged in a sibling file LANDED. Trigger is routine: a
# `git submodule add` / pointer bump in the same commit as application code.
# The gitlink must be SKIPPED (it has no bytes to scan) while its siblings are
# still scanned. RED pre-fix: COMMITTED + "could not materialize staged content".
#
# HERMETIC: the submodule source is a LOCAL directory created here — never a
# network remote (house rule; a live `gh repo create` leaked a real repo
# 2026-07-06). `-c protocol.file.allow=always` is required because git ≥2.38
# refuses the file:// transport for submodules by default.
echo "=== T-index-gitlink-not-blinding ==="
# mk_submodule_src <dir>: a throwaway LOCAL repo with one commit, usable as a
# submodule source over a plain filesystem path.
mk_submodule_src() {
  local s="$1"
  mkdir -p "$s"
  ( cd "$s" \
      && git init -q \
      && git config user.email "bl132@test.invalid" \
      && git config user.name  "BL-132 Test" \
      && echo "submodule payload" > lib.txt \
      && git add lib.txt \
      && git commit -q -m "chore: sub init" ) || return 1
}
# gitlink_mode <repo> <path>: the INDEX mode of <path> (160000 iff a gitlink).
gitlink_mode() { ( cd "$1" && git ls-files -s -- "$2" 2>/dev/null | awk 'NR==1{print $1}' ); }

if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-index-gitlink-not-blinding" "semgrep ABSENT — skip, not pass"
  skip_ "T-index-gitlink-only-honest"  "semgrep ABSENT — skip, not pass"
else
  SUBSRC="$TOPTMP/subsrc"
  R5="$TOPTMP/gitlink"
  if ! mk_submodule_src "$SUBSRC"; then
    fail_ "T-index-gitlink-not-blinding" "submodule source repo setup failed"
    fail_ "T-index-gitlink-only-honest"  "submodule source repo setup failed"
  elif ! mk_repo "$R5" "$EMITTED"; then
    fail_ "T-index-gitlink-not-blinding" "repo setup failed"
    fail_ "T-index-gitlink-only-honest"  "repo setup failed"
  else
    printf '%s\n' "$XSS_TS" > "$R5/app.ts"
    ( cd "$R5" \
        && git add app.ts \
        && git -c protocol.file.allow=always submodule add -q "$SUBSRC" sub ) >"$TOPTMP/o5setup" 2>&1
    GLMODE="$(gitlink_mode "$R5" sub)"
    if [ "$GLMODE" != "160000" ]; then
      # No gitlink got staged => the fixture proves NOTHING. Loud skip, never a pass.
      skip_ "T-index-gitlink-not-blinding" "could not stage a submodule gitlink (mode='$GLMODE'; submodule add: $(tail -2 "$TOPTMP/o5setup" | tr '\n' '|')) — regression UNPROVEN here"
      skip_ "T-index-gitlink-only-honest"  "could not stage a submodule gitlink — receipt honesty UNPROVEN here"
    else
      H0="$(head_of "$R5")"
      if ( cd "$R5" && git commit -m "feat: app + submodule" ) >"$TOPTMP/o5" 2>&1; then V=COMMITTED; else V=REFUSED; fi
      H1="$(head_of "$R5")"
      if [ "$V" = "COMMITTED" ]; then
        if grep -qF 'could not materialize staged content' "$TOPTMP/o5"; then
          fail_ "T-index-gitlink-not-blinding" "the staged gitlink ABORTED materialization — every sibling target was discarded, the commit went NOTRUN and the staged innerHTML XSS LANDED (R-270-1): $(grep -E 'SAST NOT ENFORCED|could not materialize' "$TOPTMP/o5" | head -1)"
        elif not_enforced "$TOPTMP/o5"; then
          skip_ "T-index-gitlink-not-blinding" "scanner did not run (registry unreachable?) — blocking UNPROVEN here"
        else
          fail_ "T-index-gitlink-not-blinding" "staged innerHTML XSS COMMITTED alongside a gitlink: $(grep -E '\[OK\]|\[BLOCKED\]' "$TOPTMP/o5" | head -1)"
        fi
      elif ! grep -q "\[BLOCKED\]" "$TOPTMP/o5"; then
        fail_ "T-index-gitlink-not-blinding" "refused but without [BLOCKED] (wrong reason): $(tail -3 "$TOPTMP/o5" | tr '\n' '|')"
      elif [ "$H0" != "$H1" ]; then
        fail_ "T-index-gitlink-not-blinding" "non-zero exit but HEAD MOVED"
      elif ! grep -q 'app.ts' "$TOPTMP/o5"; then
        fail_ "T-index-gitlink-not-blinding" "blocked, but the finding did not name the real path app.ts"
      elif grep -qE '/var/folders/|/tmp/tmp\.' "$TOPTMP/o5"; then
        fail_ "T-index-gitlink-not-blinding" "raw mktemp temp-tree prefix leaked into output (F3)"
      elif grep -qE '(^|[^A-Za-z0-9_./-])[0-9]+/app\.ts' "$TOPTMP/o5"; then
        fail_ "T-index-gitlink-not-blinding" "the per-index temp SUBDIR number leaked into the reported path — the path-mapping sed strips the tree but not the index dir"
      else
        pass "T-index-gitlink-not-blinding: staged gitlink SKIPPED, its sibling staged vuln still scanned + REFUSED, real path shown"
      fi

      # ── T-index-gitlink-only-honest (receipt honesty) ────────────────────────
      # A submodule POINTER BUMP stages ONLY the gitlink. Nothing is scannable, so
      # the hook must NOT print an "[OK] semgrep: SAST ran on N staged file(s)"
      # receipt it did not earn — 0 materialized targets => loud NOTRUN.
      ( cd "$SUBSRC" && echo "bump" >> lib.txt && git add lib.txt && git commit -q -m "chore: bump" ) >/dev/null 2>&1
      ( cd "$R5" && git checkout -q -- . 2>/dev/null; git reset -q ) >/dev/null 2>&1
      rm -f "$R5/app.ts"
      ( cd "$R5/sub" && git fetch -q origin && git checkout -q "$( cd "$SUBSRC" && git rev-parse HEAD )" ) >/dev/null 2>&1
      ( cd "$R5" && git add sub ) >/dev/null 2>&1
      GL_ONLY="$( cd "$R5" && git diff --cached --name-only --diff-filter=ACM | tr '\n' ' ' )"
      if [ "$GL_ONLY" != "sub " ]; then
        skip_ "T-index-gitlink-only-honest" "could not stage a gitlink-ONLY index (staged='$GL_ONLY') — receipt honesty UNPROVEN here"
      else
        H0="$(head_of "$R5")"
        if ( cd "$R5" && git commit -m "chore: bump submodule pointer" ) >"$TOPTMP/o6" 2>&1; then V6=COMMITTED; else V6=REFUSED; fi
        H1="$(head_of "$R5")"
        if grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/o6"; then
          fail_ "T-index-gitlink-only-honest" "a gitlink-ONLY commit claimed a scan it did not do: $(grep -F '[OK] semgrep: SAST ran' "$TOPTMP/o6" | head -1)"
        elif [ "$V6" != "COMMITTED" ] || [ "$H0" = "$H1" ]; then
          fail_ "T-index-gitlink-only-honest" "a pointer bump must LAND (gitlinks are not blockable content); verdict=$V6 moved=$([ "$H0" != "$H1" ] && echo YES || echo NO): $(tail -3 "$TOPTMP/o6" | tr '\n' '|')"
        elif ! not_enforced "$TOPTMP/o6"; then
          fail_ "T-index-gitlink-only-honest" "0 scannable targets but no loud NOTRUN — the operator is told nothing: $(tail -3 "$TOPTMP/o6" | tr '\n' '|')"
        else
          pass "T-index-gitlink-only-honest: gitlink-only commit LANDS, no unearned [OK] receipt, loud NOTRUN instead"
        fi
      fi
    fi
  fi
fi

# ── T-index-case-collision (BL-178) ──────────────────────────────────────────
# Two staged paths differing ONLY in case collide in a single FLAT temp tree on a
# case-INSENSITIVE filesystem (macOS APFS, Windows NTFS): the second
# `git cat-file blob` write lands on the SAME on-disk path and clobbers the first.
# If the CLEAN blob materializes last the vuln blob is LOST and the commit lands
# `[OK]`. The F2 size guard cannot see it — each write is internally consistent;
# it is the EARLIER blob that was destroyed. Per-index subdirs close it.
#
# The index is built with `git update-index --cacheinfo` on purpose: a case-
# INSENSITIVE CHECKOUT physically cannot hold both worktree files, but the INDEX
# can and routinely does (a tree authored on Linux, cloned on macOS). git's
# `:<path>` index lookup stays case-EXACT there — the fixture asserts that.
echo "=== T-index-case-collision ==="
CASE_INSENSITIVE_FS=0
printf 'x' > "$TOPTMP/CaseFsProbe.tmp"
[ -f "$TOPTMP/casefsprobe.tmp" ] && CASE_INSENSITIVE_FS=1
rm -f "$TOPTMP/CaseFsProbe.tmp" "$TOPTMP/casefsprobe.tmp"
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-index-case-collision" "semgrep ABSENT — skip, not pass"
elif [ "$CASE_INSENSITIVE_FS" -eq 0 ]; then
  skip_ "T-index-case-collision" "filesystem is case-SENSITIVE — the temp-tree collision is UNOBSERVABLE here and this case would pass vacuously (BL-178 needs APFS/NTFS)"
else
  R7="$TOPTMP/casecol"
  if ! mk_repo "$R7" "$EMITTED"; then
    fail_ "T-index-case-collision" "repo setup failed"
  else
    CC_V="$( printf '%s\n' "$XSS_TS"  | ( cd "$R7" && git hash-object -w --stdin ) )"
    CC_C="$( printf '%s\n' "$SAFE_TS" | ( cd "$R7" && git hash-object -w --stdin ) )"
    ( cd "$R7" && git update-index --add --cacheinfo "100644,$CC_V,App.ts" \
                && git update-index --add --cacheinfo "100644,$CC_C,app.ts" ) >/dev/null 2>&1
    CC_ORDER="$( cd "$R7" && git diff --cached --name-only --diff-filter=ACM | tr '\n' ' ' )"
    CC_UPPER_IS_VULN=0
    ( cd "$R7" && git cat-file blob ":App.ts" 2>/dev/null ) | grep -q 'innerHTML' && CC_UPPER_IS_VULN=1
    CC_LOWER_IS_CLEAN=0
    ( cd "$R7" && git cat-file blob ":app.ts" 2>/dev/null ) | grep -q 'textContent' && CC_LOWER_IS_CLEAN=1
    if [ "$CC_ORDER" != "App.ts app.ts " ]; then
      # Materialization order matters: the CLEAN blob must be written LAST, or the
      # flat tree would clobber the clean copy with the vuln and pass for free.
      skip_ "T-index-case-collision" "the case-only pair did not stage in the expected order (staged='$CC_ORDER') — collision direction UNPROVEN here"
    elif [ "$CC_UPPER_IS_VULN" -ne 1 ] || [ "$CC_LOWER_IS_CLEAN" -ne 1 ]; then
      skip_ "T-index-case-collision" "git's :<path> index lookup is not case-EXACT on this host (App.ts vuln=$CC_UPPER_IS_VULN, app.ts clean=$CC_LOWER_IS_CLEAN) — fixture cannot distinguish the two blobs"
    else
      H0="$(head_of "$R7")"
      if ( cd "$R7" && git commit -m "feat: case-only pair" ) >"$TOPTMP/o7" 2>&1; then V=COMMITTED; else V=REFUSED; fi
      H1="$(head_of "$R7")"
      if [ "$V" = "COMMITTED" ]; then
        if not_enforced "$TOPTMP/o7"; then
          skip_ "T-index-case-collision" "scanner did not run (registry unreachable?) — collision UNPROVEN here"
        else
          fail_ "T-index-case-collision" "the vuln blob App.ts was CLOBBERED in the flat temp tree by the clean app.ts and COMMITTED (BL-178): $(grep -E '\[OK\]|\[BLOCKED\]' "$TOPTMP/o7" | head -1)"
        fi
      elif ! grep -q "\[BLOCKED\]" "$TOPTMP/o7"; then
        fail_ "T-index-case-collision" "refused but without [BLOCKED] (wrong reason): $(tail -3 "$TOPTMP/o7" | tr '\n' '|')"
      elif [ "$H0" != "$H1" ]; then
        fail_ "T-index-case-collision" "non-zero exit but HEAD MOVED"
      elif ! grep -q 'App\.ts' "$TOPTMP/o7"; then
        fail_ "T-index-case-collision" "blocked, but the finding did not name the REAL staged path App.ts (case-exact): $(tail -5 "$TOPTMP/o7" | tr '\n' '|')"
      elif grep -qE '/var/folders/|/tmp/tmp\.' "$TOPTMP/o7"; then
        fail_ "T-index-case-collision" "raw mktemp temp-tree prefix leaked into output (F3)"
      elif grep -qE '(^|[^A-Za-z0-9_./-])[0-9]+/App\.ts' "$TOPTMP/o7"; then
        fail_ "T-index-case-collision" "the per-index temp SUBDIR number leaked into the reported path — the path-mapping sed strips the tree but not the index dir"
      else
        pass "T-index-case-collision: case-only-differing staged blobs no longer collide, the vuln is REFUSED, real path App.ts shown"
      fi
    fi
  fi
fi

# ── T-index-stage-syntax-path (R-270-1B regression) ──────────────────────────
# git's REVISION syntax reads `:<0-3>:<path>` as a MERGE-STAGE reference, so a staged
# path whose REPO-ROOT name begins with `0:`, `1:`, `2:` or `3:` makes the BARE
# `git cat-file -t ":$soif_p"` FAIL on a perfectly healthy, fully readable blob
# ("fatal: path 'decoy.js' does not exist ..."). Verified boundaries (git 2.50.1):
#   0:x.js / 2:x.js / 3:x.js -> FAIL     4:x.js -> blob (only 0-3 are stage digits)
#   2evil.js -> blob (the colon is required)   sub/2:x.js -> blob (repo ROOT only)
# Such an entry is NOT a gitlink, so # BL-132-GITLINK-SKIP does not `continue` it: it
# fell through to the loop's then-existing `soif_idx_ok=0; break` (that statement is
# GONE — # BL-182-PER-ENTRY-SKIP retired it; this paragraph is history, not a code
# citation), which DISCARDED every already-materialized sibling target and routed the
# WHOLE commit to the loud NOTRUN — so a genuinely vulnerable SIBLING file LANDED. That
# was a security-lane regression versus main, the same "one bad entry blinds the whole
# commit" mechanism as R-270-1 (the gitlink bug). THE CASE STILL EARNS ITS KEEP after
# BL-182: without the `:0:` prefix such an entry becomes an UNREADABLE entry, which now
# forfeits the commit's [OK] receipt over content that was readable all along.
# The fix pins the stage explicitly (`:0:$soif_p`, # BL-132-STAGE0-REF) at all three
# cat-file sites; `:0:` still resolves ordinary paths. The `:(literal)` gitlink probe
# is a PATHSPEC, not a revision, and was verified immune — it is deliberately unchanged.
# RED pre-fix: COMMITTED + "could not materialize staged content".
echo "=== T-index-stage-syntax-path ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-index-stage-syntax-path" "semgrep ABSENT — skip, not pass"
else
  R8="$TOPTMP/stagesyn"
  SS_DECOY='0:decoy.js'
  if ! mk_repo "$R8" "$EMITTED"; then
    fail_ "T-index-stage-syntax-path" "repo setup failed"
  else
    # BOTH files carry a sink the shipped rulesets catch, so BOTH must be NAMED: the
    # decoy proves the `0:`-prefixed entry was itself materialized and scanned (not
    # merely skipped), the sibling proves it did not blind the rest of the commit.
    printf '%s\n' "$IA_SINK" > "$R8/$SS_DECOY" 2>/dev/null || true
    printf '%s\n' "$XSS_TS"  > "$R8/app.ts"
    ( cd "$R8" && git add -- "$SS_DECOY" app.ts ) >/dev/null 2>&1
    SS_STAGED="$( cd "$R8" && git diff --cached --name-only --diff-filter=ACM | tr '\n' ' ' )"
    # Fixture-validity probes: the case proves nothing unless BOTH paths really staged
    # AND this git really does show the collision (bare form fails, stage-0 succeeds).
    SS_BARE_FAILS=0
    ( cd "$R8" && git cat-file -t ":$SS_DECOY" ) >/dev/null 2>&1 || SS_BARE_FAILS=1
    SS_STAGE0_OK=0
    [ "$( cd "$R8" && git cat-file -t ":0:$SS_DECOY" 2>/dev/null )" = "blob" ] && SS_STAGE0_OK=1
    if [ "$SS_STAGED" != "$SS_DECOY app.ts " ]; then
      skip_ "T-index-stage-syntax-path" "could not stage the '$SS_DECOY' + app.ts pair (staged='$SS_STAGED') — a ':' in a filename may be unrepresentable here; regression UNPROVEN"
    elif [ "$SS_BARE_FAILS" -ne 1 ] || [ "$SS_STAGE0_OK" -ne 1 ]; then
      skip_ "T-index-stage-syntax-path" "this git shows no stage-syntax collision (bare-fails=$SS_BARE_FAILS stage0-blob=$SS_STAGE0_OK) — the case would pass vacuously"
    else
      H0="$(head_of "$R8")"
      if ( cd "$R8" && git commit -m "feat: decoy + app" ) >"$TOPTMP/o8" 2>&1; then V=COMMITTED; else V=REFUSED; fi
      H1="$(head_of "$R8")"
      if [ "$V" = "COMMITTED" ]; then
        if grep -qF 'could not materialize staged content' "$TOPTMP/o8"; then
          fail_ "T-index-stage-syntax-path" "the staged '$SS_DECOY' hit git's :<stage>:<path> revision syntax on a HEALTHY blob, ABORTED materialization and routed the WHOLE commit to NOTRUN — the sibling app.ts innerHTML XSS LANDED (R-270-1B): $(grep -E 'SAST NOT ENFORCED|could not materialize' "$TOPTMP/o8" | head -1)"
        elif not_enforced "$TOPTMP/o8"; then
          skip_ "T-index-stage-syntax-path" "scanner did not run (registry unreachable?) — blocking UNPROVEN here"
        else
          fail_ "T-index-stage-syntax-path" "staged sinks COMMITTED alongside a '$SS_DECOY' path: $(grep -E '\[OK\]|\[BLOCKED\]' "$TOPTMP/o8" | head -1)"
        fi
      elif ! grep -q "\[BLOCKED\]" "$TOPTMP/o8"; then
        fail_ "T-index-stage-syntax-path" "refused but without [BLOCKED] (wrong reason): $(tail -3 "$TOPTMP/o8" | tr '\n' '|')"
      elif [ "$H0" != "$H1" ]; then
        fail_ "T-index-stage-syntax-path" "non-zero exit but HEAD MOVED"
      elif ! grep -qF "$SS_DECOY" "$TOPTMP/o8"; then
        fail_ "T-index-stage-syntax-path" "blocked, but the '$SS_DECOY' entry itself was never NAMED — it was silently skipped rather than scanned"
      elif ! grep -q 'app\.ts' "$TOPTMP/o8"; then
        fail_ "T-index-stage-syntax-path" "blocked, but the SIBLING app.ts was not NAMED — the '$SS_DECOY' entry still cost the commit its sibling coverage"
      elif grep -qE '/var/folders/|/tmp/tmp\.' "$TOPTMP/o8"; then
        fail_ "T-index-stage-syntax-path" "raw mktemp temp-tree prefix leaked into output (F3)"
      elif grep -qE '(^|[^A-Za-z0-9_./-])[0-9][0-9]*/(0:decoy\.js|app\.ts)' "$TOPTMP/o8"; then
        fail_ "T-index-stage-syntax-path" "the per-index temp SUBDIR number leaked into a reported path — the operator is shown a path that exists nowhere"
      else
        pass "T-index-stage-syntax-path: a repo-root '$SS_DECOY' no longer collides with git stage syntax — BOTH it and its sibling app.ts are scanned + REFUSED, both real repo-relative paths shown"
      fi
    fi
  fi
fi

# ── T-rename-edit-scanned (BL-179) ───────────────────────────────────────────
# `diff.renames` defaults to TRUE, so a commit that RENAMES a file and EDITS it in the
# same breath is a single status-R entry — and the old `--diff-filter=ACM` EXCLUDED R.
# soif_staged came back EMPTY, the arm's `-gt 0` wrapper had NO `else`, and the whole
# scanner was skipped IN SILENCE: no [OK], no [BLOCKED], not even the loud NOTRUN.
# Rename-and-edit is one of the most routine commit shapes there is, so this was a
# security tripwire that a plain refactor walked straight through. Filter -> ACMR; the
# `-z --name-only` output for an R entry is the DESTINATION, and `:0:<dest>` resolves
# to the staged blob, so the materialization loop needs no change.
# RED pre-fix: COMMITTED, HEAD moves, the sink is in `git show HEAD:new.ts`, and the
# log carries ZERO SAST lines.
echo "=== T-rename-edit-scanned ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-rename-edit-scanned" "semgrep ABSENT — skip, not pass"
else
  R9="$TOPTMP/renedit"
  if ! mk_repo_seeded "$R9" "$EMITTED" old.ts "$REN_SAFE"; then
    fail_ "T-rename-edit-scanned" "repo setup failed"
  else
    ( cd "$R9" && git mv old.ts new.ts ) >/dev/null 2>&1
    printf '%s\n' "$REN_VULN" > "$R9/new.ts"
    # PATHSPEC-SCOPED to the DESTINATION ONLY, and both halves of that matter:
    #   • a bare `git add -A` also sweeps in the untracked .semgrep/soif-dom-sinks.yml
    #     mk_repo drops in, giving the arm a second staged entry to scan and receipt —
    #     the case would then "see SAST output" while the renamed destination went
    #     unscanned, i.e. pass for entirely the wrong reason;
    #   • the source must NOT be listed: `git mv` already removed old.ts from the index
    #     AND the worktree, so `git add -- old.ts new.ts` dies with "pathspec 'old.ts'
    #     did not match any files" and stages NOTHING — the index keeps the pre-edit
    #     blob, the rename scores 100%, and the fixture silently has no vuln in it.
    ( cd "$R9" && git add -- new.ts ) >/dev/null 2>&1
    RN_STATUS="$( cd "$R9" && git diff --cached --name-status | tr '\n' ' ' )"
    # FIXTURE-VALIDITY PROBE, learned the hard way: an add that stages nothing leaves a
    # 100%-similar rename with no sink in it, and every downstream assertion then passes
    # for free. Assert the sink is really in the STAGED destination blob.
    RN_HAS_SINK=0
    ( cd "$R9" && git cat-file blob ":0:new.ts" 2>/dev/null ) | grep -q 'innerHTML' && RN_HAS_SINK=1
    if [ "$RN_HAS_SINK" -ne 1 ]; then
      fail_ "T-rename-edit-scanned" "FIXTURE INVALID — the staged destination blob does not contain the innerHTML sink (name-status='$RN_STATUS'); the edit never reached the index, so the case would prove nothing"
    elif ! ( cd "$R9" && git diff --cached --name-status | grep -q '^R' ); then
      skip_ "T-rename-edit-scanned" "git did not report a RENAME here (name-status='$RN_STATUS') — either diff.renames is off or the edit dropped similarity below the threshold, so the ACM-excludes-R defect cannot trigger and this case would pass vacuously"
    else
      H0="$(head_of "$R9")"
      if ( cd "$R9" && git commit -m "refactor: rename and harden render" ) >"$TOPTMP/o9" 2>&1; then V=COMMITTED; else V=REFUSED; fi
      H1="$(head_of "$R9")"
      if ! any_sast_line "$TOPTMP/o9"; then
        fail_ "T-rename-edit-scanned" "the SAST arm said NOTHING AT ALL on a rename-and-edit commit (name-status='$RN_STATUS') — no [OK], no [BLOCKED], not even the loud NOTRUN: --diff-filter=ACM excludes R, so soif_staged was EMPTY and the arm was skipped in silence (BL-179); verdict=$V"
      elif [ "$V" = "COMMITTED" ]; then
        if not_enforced "$TOPTMP/o9"; then
          skip_ "T-rename-edit-scanned" "scanner did not run (registry unreachable?) — blocking UNPROVEN here"
        else
          fail_ "T-rename-edit-scanned" "the rename DESTINATION's innerHTML XSS COMMITTED: $(grep -E '\[OK\]|\[BLOCKED\]' "$TOPTMP/o9" | head -1)"
        fi
      elif ! grep -q "\[BLOCKED\]" "$TOPTMP/o9"; then
        fail_ "T-rename-edit-scanned" "refused but without [BLOCKED] (wrong reason): $(tail -3 "$TOPTMP/o9" | tr '\n' '|')"
      elif [ "$H0" != "$H1" ]; then
        fail_ "T-rename-edit-scanned" "non-zero exit but HEAD MOVED"
      elif ! grep -q 'new\.ts' "$TOPTMP/o9"; then
        fail_ "T-rename-edit-scanned" "blocked, but the finding did not name the rename DESTINATION new.ts: $(tail -5 "$TOPTMP/o9" | tr '\n' '|')"
      elif grep -qE '/var/folders/|/tmp/tmp\.' "$TOPTMP/o9"; then
        fail_ "T-rename-edit-scanned" "raw mktemp temp-tree prefix leaked into output (F3)"
      else
        pass "T-rename-edit-scanned: a rename-and-edit commit IS scanned — the destination's staged XSS is REFUSED and new.ts is named (BL-179)"
      fi
    fi
  fi
fi

# ── T-rename-only-not-silent (BL-179) ────────────────────────────────────────
# The residual rename case: R100, no content change. It has staged content (the
# destination), so it MUST be scanned and receipted — and pre-fix it produced the same
# total silence as the rename-and-edit shape. This case exists to pin the SILENCE, not
# the blocking: the commit is clean, so the only observable that can distinguish "the
# gate ran and cleared it" from "the gate was never asked" is the receipt itself.
echo "=== T-rename-only-not-silent ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-rename-only-not-silent" "semgrep ABSENT — skip, not pass"
else
  RA="$TOPTMP/renonly"
  if ! mk_repo_seeded "$RA" "$EMITTED" old.ts "$REN_SAFE"; then
    fail_ "T-rename-only-not-silent" "repo setup failed"
  else
    ( cd "$RA" && git mv old.ts new.ts ) >/dev/null 2>&1
    RA_STATUS="$( cd "$RA" && git diff --cached --name-status | tr '\n' ' ' )"
    H0="$(head_of "$RA")"
    if ( cd "$RA" && git commit -m "refactor: rename render module" ) >"$TOPTMP/oA" 2>&1; then V=COMMITTED; else V=REFUSED; fi
    H1="$(head_of "$RA")"
    case "$RA_STATUS" in R*) RA_IS_RENAME=1 ;; *) RA_IS_RENAME=0 ;; esac
    if [ "$RA_IS_RENAME" -ne 1 ]; then
      skip_ "T-rename-only-not-silent" "git did not report a pure RENAME here (name-status='$RA_STATUS') — case would pass vacuously"
    elif ! any_sast_line "$TOPTMP/oA"; then
      fail_ "T-rename-only-not-silent" "a rename-ONLY commit produced NO SAST output whatsoever (name-status='$RA_STATUS') — the operator cannot tell a clean scan from a scan that never happened (BL-179 silence); verdict=$V"
    elif [ "$V" != "COMMITTED" ] || [ "$H0" = "$H1" ]; then
      fail_ "T-rename-only-not-silent" "a clean rename must LAND; verdict=$V moved=$([ "$H0" != "$H1" ] && echo YES || echo NO): $(tail -3 "$TOPTMP/oA" | tr '\n' '|')"
    elif grep -qF '[BLOCKED]' "$TOPTMP/oA"; then
      fail_ "T-rename-only-not-silent" "a content-free rename was BLOCKED (false block): $(grep -F '[BLOCKED]' "$TOPTMP/oA" | head -1)"
    else
      pass "T-rename-only-not-silent: a rename-only commit LANDS and is RECEIPTED — the arm is never silent (BL-179)"
    fi
  fi
fi

# ── T-delete-only-honest (BL-179, the sharp edge of the filter) ──────────────
# D MUST STAY OUT of the filter. The tempting move is to copy the BL-125 test arm's
# `--diff-filter=ACMDR` wholesale, but the two arms want different things: BL-125 must
# RUN THE TESTS when a sanitizer is deleted, while this arm must SCAN CONTENT — and a
# deleted path has NO staged content. With D in, `git cat-file -t ":0:<deleted>"` fails
# (verified here: exit 128), which manufactures an unreadable entry and re-creates the
# very class BL-182 retires. So: a deletion-only commit must LAND, must NOT claim it
# could not materialize anything, and must still SAY SOMETHING.
echo "=== T-delete-only-honest ==="
RB="$TOPTMP/delonly"
if ! mk_repo_seeded "$RB" "$EMITTED" gone.ts "$REN_SAFE"; then
  fail_ "T-delete-only-honest" "repo setup failed"
else
  ( cd "$RB" && git rm -q gone.ts ) >/dev/null 2>&1
  RB_STAGED="$( cd "$RB" && git diff --cached --name-status | tr '\n' ' ' )"
  H0="$(head_of "$RB")"
  if ( cd "$RB" && git commit -m "chore: drop dead module" ) >"$TOPTMP/oB" 2>&1; then V=COMMITTED; else V=REFUSED; fi
  H1="$(head_of "$RB")"
  # `--name-status` separates the status letter from the path with a TAB, not a space,
  # so this must be a prefix match — a `${var%% *}` word-split silently never matches
  # and the case would LOUD-SKIP forever while looking healthy.
  case "$RB_STAGED" in D*) RB_IS_DELETE=1 ;; *) RB_IS_DELETE=0 ;; esac
  if [ "$RB_IS_DELETE" -ne 1 ]; then
    skip_ "T-delete-only-honest" "could not stage a pure deletion (name-status='$RB_STAGED') — case UNPROVEN here"
  elif [ "$V" != "COMMITTED" ] || [ "$H0" = "$H1" ]; then
    fail_ "T-delete-only-honest" "a deletion-only commit must LAND; verdict=$V moved=$([ "$H0" != "$H1" ] && echo YES || echo NO): $(tail -5 "$TOPTMP/oB" | tr '\n' '|')"
  elif grep -qF 'could not materialize staged content' "$TOPTMP/oB"; then
    fail_ "T-delete-only-honest" "a pure DELETION was fed to the materialization loop as a non-blob — D leaked into the staged filter (the BL-125 ACMDR shape copied into a content scanner): $(grep -F 'could not materialize' "$TOPTMP/oB" | head -1)"
  elif ! any_sast_line "$TOPTMP/oB"; then
    fail_ "T-delete-only-honest" "a deletion-only commit produced NO SAST output at all — the arm's no-else silence (BL-179); verdict=$V"
  else
    pass "T-delete-only-honest: a deletion-only commit LANDS, is honestly receipted, and never reaches the loop with a blob-less entry (BL-179)"
  fi
fi

# ── T-typechange-scanned (BL-179, the filter's fourth letter) ────────────────
# A staged TYPE CHANGE — git status letter T — is a real staged BLOB with real content,
# and `--diff-filter=ACMR` EXCLUDED it. Materializing a symlink into a regular file
# (`rm link.ts` then write it) is ordinary repo hygiene, and the resulting index entry
# holds whatever bytes the new regular file carries.
#   THIS IS NOT THE SAME SHAPE AS THE RENAME DEFECT, and that is why it needs its own
#   case. A rename-only commit left soif_staged EMPTY, so the # BL-179-EMPTY-STAGED arm
#   at least SAID something. Here a clean sibling keeps soif_staged non-empty, so the
#   commit never reaches that arm: it prints the `[OK] semgrep: SAST ran on N staged
#   file(s)` RECEIPT while N counts only the sibling and the unscanned T entry carries
#   the sink. That is the unearned-receipt class (# BL-182-NO-UNEARNED-RECEIPT) reached
#   through the FILTER instead of through the materialization loop — the loop never sees
#   the entry, so the guard after it cannot fire.
#   T IS SAFE TO INCLUDE WHERE D IS NOT (verified on this host, git 2.50.1):
#   `git cat-file -t ":0:<path>"` returns `blob` for a T entry in BOTH directions —
#   symlink->file (index mode 100644) and file->symlink (index mode 120000) — and for
#   gitlink->file. So, unlike D, T never manufactures a phantom unreadable entry and the
#   materialization loop needs no change. (A hypothetical ->gitlink T would present mode
#   160000 and be absorbed by # BL-132-GITLINK-SKIP, which is already correct.)
# RED pre-fix: COMMITTED, HEAD moves, `[OK] … on 1 staged file(s)` printed over TWO
# staged blobs, and `git show HEAD:link.ts` still holds the innerHTML sink.
echo "=== T-typechange-scanned ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-typechange-scanned" "semgrep ABSENT — skip, not pass"
else
  RT="$TOPTMP/typechange"
  if ! mk_repo_typechange "$RT" "$EMITTED"; then
    skip_ "T-typechange-scanned" "this host could not seed a mode-120000 symlink index entry (no symlink support / core.symlinks=false) — the type-change generator is UNAVAILABLE and the case would degrade into an ordinary M"
  else
    rm -f "$RT/link.ts"
    printf '%s\n' "$XSS_TS"  > "$RT/link.ts"     # the symlink becomes a REGULAR FILE carrying the sink
    printf '%s\n' "$SAFE_TS" > "$RT/app.ts"      # a CLEAN sibling, so soif_staged is never empty
    ( cd "$RT" && git add -- link.ts app.ts ) >/dev/null 2>&1
    RT_STATUS="$( cd "$RT" && git diff --cached --name-status | tr '\n' ' ' )"
    RT_TYPE="$( cd "$RT" && git cat-file -t ":0:link.ts" 2>/dev/null )"
    RT_HAS_SINK=0
    ( cd "$RT" && git cat-file blob ":0:link.ts" 2>/dev/null ) | grep -q 'innerHTML' && RT_HAS_SINK=1
    # FIXTURE-VALIDITY PROBES, all three load-bearing: without the `^T` probe a host that
    # reported `M` would pass this case for free (M was always in the filter); without the
    # blob/sink probes a staged entry with no sink in it proves nothing about scanning.
    if ! ( cd "$RT" && git diff --cached --name-status | grep -q '^T' ); then
      skip_ "T-typechange-scanned" "git did not report a TYPE CHANGE here (name-status='$RT_STATUS') — the T-excluded-by-the-filter defect cannot trigger and this case would pass vacuously"
    elif [ "$RT_TYPE" != "blob" ] || [ "$RT_HAS_SINK" -ne 1 ]; then
      fail_ "T-typechange-scanned" "FIXTURE INVALID — the staged type-change entry is not a sink-carrying blob (index type='$RT_TYPE' want blob, sink=$RT_HAS_SINK want 1; name-status='$RT_STATUS')"
    else
      H0="$(head_of "$RT")"
      if ( cd "$RT" && git commit -m "refactor: materialize the symlink" ) >"$TOPTMP/oT" 2>&1; then V=COMMITTED; else V=REFUSED; fi
      H1="$(head_of "$RT")"
      RT_LANDED="$( cd "$RT" && git show "HEAD:link.ts" 2>/dev/null | grep -c 'innerHTML' | tr -d '[:space:]' )"
      if ! any_sast_line "$TOPTMP/oT"; then
        fail_ "T-typechange-scanned" "the SAST arm said NOTHING AT ALL on a type-change commit (name-status='$RT_STATUS'); verdict=$V"
      elif grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/oT"; then
        fail_ "T-typechange-scanned" "an UNEARNED [OK] receipt — the staged TYPE CHANGE was excluded by --diff-filter (letter T), so N counts only the sibling while the unscanned entry carries the sink (BL-179); receipt: $(grep -F '[OK] semgrep: SAST ran' "$TOPTMP/oT" | head -1); sink landed in HEAD:link.ts=$RT_LANDED"
      elif [ "$V" = "COMMITTED" ]; then
        if not_enforced "$TOPTMP/oT"; then
          skip_ "T-typechange-scanned" "scanner did not run (registry unreachable?) — blocking UNPROVEN here"
        else
          fail_ "T-typechange-scanned" "the type-change entry's innerHTML XSS COMMITTED (sink in HEAD:link.ts=$RT_LANDED): $(grep -E '\[OK\]|\[BLOCKED\]' "$TOPTMP/oT" | head -1)"
        fi
      elif ! grep -qF '[BLOCKED]' "$TOPTMP/oT"; then
        fail_ "T-typechange-scanned" "refused but without [BLOCKED] (wrong reason): $(tail -3 "$TOPTMP/oT" | tr '\n' '|')"
      elif [ "$H0" != "$H1" ]; then
        fail_ "T-typechange-scanned" "non-zero exit but HEAD MOVED"
      elif [ "$RT_LANDED" != "0" ]; then
        fail_ "T-typechange-scanned" "blocked, but the sink is present in the committed tree (HEAD:link.ts matches=$RT_LANDED)"
      elif ! grep -q 'link\.ts' "$TOPTMP/oT"; then
        fail_ "T-typechange-scanned" "blocked, but the finding did not name the type-change path link.ts: $(tail -5 "$TOPTMP/oT" | tr '\n' '|')"
      elif grep -qE '/var/folders/|/tmp/tmp\.' "$TOPTMP/oT"; then
        fail_ "T-typechange-scanned" "raw mktemp temp-tree prefix leaked into output (F3)"
      else
        pass "T-typechange-scanned: a staged TYPE CHANGE is scanned — its innerHTML XSS is REFUSED, link.ts is named, and no [OK] is printed over a set the filter truncated (BL-179)"
      fi
    fi
  fi
fi

# ── T-partial-clean-no-receipt (BL-182) ──────────────────────────────────────
# THE SECURITY CONTRACT, HALF ONE. One staged entry cannot be materialized; every
# OTHER staged entry scans CLEAN. That is NOT a clean commit — and it must never print
# the `[OK] semgrep: SAST ran on N staged file(s)` receipt, because the entry that was
# never read is exactly where a sink would hide (here it literally does: the unreadable
# blob carries the innerHTML sink). Loud NOTRUN, and NAME the entry so the operator can
# act on it. RED pre-fix: the whole-commit abort NOTRUNs without naming anything, and
# leaks a raw `File name too long` tool diagnostic into the commit transcript.
echo "=== T-partial-clean-no-receipt ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-partial-clean-no-receipt" "semgrep ABSENT — skip, not pass"
  skip_ "T-partial-vuln-still-blocks" "semgrep ABSENT — skip, not pass"
  skip_ "T-gitlink-not-counted-unread" "semgrep ABSENT — skip, not pass"
elif fs_can_hold_name "$LONG_NAME"; then
  skip_ "T-partial-clean-no-receipt" "this filesystem accepts a ${#LONG_NAME}-byte path COMPONENT — the unreadable-entry generator does not fire here and the case would pass vacuously"
  skip_ "T-partial-vuln-still-blocks" "this filesystem accepts a ${#LONG_NAME}-byte path COMPONENT — generator does not fire here"
  skip_ "T-gitlink-not-counted-unread" "this filesystem accepts a ${#LONG_NAME}-byte path COMPONENT — generator does not fire here"
else
  RC="$TOPTMP/partclean"
  if ! mk_repo "$RC" "$EMITTED"; then
    fail_ "T-partial-clean-no-receipt" "repo setup failed"
  elif ! stage_index_only "$RC" "$LONG_NAME" "$XSS_TS"; then
    skip_ "T-partial-clean-no-receipt" "could not add a ${#LONG_NAME}-byte-component path to the index — generator UNAVAILABLE here"
  else
    printf '%s\n' "$SAFE_TS" > "$RC/app.ts"
    ( cd "$RC" && git add app.ts ) >/dev/null 2>&1
    RC_TYPE="$( cd "$RC" && git cat-file -t ":0:$LONG_NAME" 2>/dev/null )"
    RC_N="$( cd "$RC" && git diff --cached --name-only --diff-filter=ACMR | wc -l | tr -d '[:space:]' )"
    if [ "$RC_TYPE" != "blob" ] || [ "$RC_N" != "2" ]; then
      skip_ "T-partial-clean-no-receipt" "fixture invalid (index type='$RC_TYPE' want blob, staged=$RC_N want 2) — partial coverage UNPROVEN here"
    else
      H0="$(head_of "$RC")"
      if ( cd "$RC" && git commit -m "feat: two entries, one unreadable" ) >"$TOPTMP/oC" 2>&1; then V=COMMITTED; else V=REFUSED; fi
      H1="$(head_of "$RC")"
      if grep -qF 'semgrep could not complete' "$TOPTMP/oC"; then
        # Without this the case would PASS VACUOUSLY: a tool failure also produces a
        # loud NOTRUN with the unread entries named, so every assertion below would be
        # satisfied by the WRONG arm — the clean-but-partial path would never run.
        skip_ "T-partial-clean-no-receipt" "semgrep itself failed (registry unreachable?) — the CLEAN-but-partial arm was never exercised, so this case would pass on the tool-failure arm instead"
      elif grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/oC"; then
        fail_ "T-partial-clean-no-receipt" "an UNEARNED [OK] receipt over a PARTIAL scan — one staged entry was never read and it is the one carrying the sink: $(grep -F '[OK] semgrep: SAST ran' "$TOPTMP/oC" | head -1)"
      elif ! not_enforced "$TOPTMP/oC"; then
        fail_ "T-partial-clean-no-receipt" "partial coverage produced no loud NOTRUN — the operator is told nothing: $(tail -5 "$TOPTMP/oC" | tr '\n' '|')"
      elif ! grep -qxF "    - $LONG_NAME" "$TOPTMP/oC"; then
        fail_ "T-partial-clean-no-receipt" "the NOTRUN did not NAME the staged entry it could not read — the operator learns coverage was lost but not WHERE (BL-182); log: $(grep -c . "$TOPTMP/oC") lines, $(tail -4 "$TOPTMP/oC" | cut -c1-90 | tr '\n' '|')"
      elif grep -q 'File name too long' "$TOPTMP/oC"; then
        fail_ "T-partial-clean-no-receipt" "a raw tool diagnostic leaked into the operator's commit transcript — the 2>/dev/null is on the wrong command: $(grep -m1 'File name too long' "$TOPTMP/oC" | cut -c1-120)"
      elif [ "$V" != "COMMITTED" ] || [ "$H0" = "$H1" ]; then
        fail_ "T-partial-clean-no-receipt" "an unreadable entry must WARN, never block (BL-112 contract); verdict=$V moved=$([ "$H0" != "$H1" ] && echo YES || echo NO)"
      else
        pass "T-partial-clean-no-receipt: a clean-but-PARTIAL scan earns NO [OK] receipt — loud NOTRUN naming the unreadable entry, commit still lands (BL-182)"
      fi
    fi
  fi

  # ── T-partial-vuln-still-blocks (BL-182) ───────────────────────────────────
  # THE SECURITY CONTRACT, HALF TWO — and the regression the all-or-nothing `break`
  # actually caused. One unreadable entry used to DISCARD every already-materialized
  # sibling and route the whole commit to NOTRUN, so a sink staged in a readable
  # sibling LANDED — strictly worse than scanning nothing, because the operator's
  # other siblings were silently disarmed. Scanning the readable subset must still
  # BLOCK on what it finds there.
  echo "=== T-partial-vuln-still-blocks ==="
  RD="$TOPTMP/partvuln"
  if ! mk_repo "$RD" "$EMITTED"; then
    fail_ "T-partial-vuln-still-blocks" "repo setup failed"
  elif ! stage_index_only "$RD" "$LONG_NAME" "$SAFE_TS"; then
    skip_ "T-partial-vuln-still-blocks" "could not add the long-component path to the index — generator UNAVAILABLE here"
  else
    printf '%s\n' "$XSS_TS" > "$RD/app.ts"
    ( cd "$RD" && git add app.ts ) >/dev/null 2>&1
    RD_N="$( cd "$RD" && git diff --cached --name-only --diff-filter=ACMR | wc -l | tr -d '[:space:]' )"
    if [ "$RD_N" != "2" ]; then
      skip_ "T-partial-vuln-still-blocks" "fixture invalid (staged=$RD_N want 2) — regression UNPROVEN here"
    else
      H0="$(head_of "$RD")"
      if ( cd "$RD" && git commit -m "feat: readable sibling carries the sink" ) >"$TOPTMP/oD" 2>&1; then V=COMMITTED; else V=REFUSED; fi
      H1="$(head_of "$RD")"
      if [ "$V" = "COMMITTED" ]; then
        if grep -qF 'semgrep could not complete' "$TOPTMP/oD"; then
          skip_ "T-partial-vuln-still-blocks" "semgrep itself failed (registry unreachable?) — blocking UNPROVEN here"
        elif grep -qF 'could not materialize staged content' "$TOPTMP/oD"; then
          fail_ "T-partial-vuln-still-blocks" "ONE unreadable staged entry discarded every already-materialized sibling and routed the WHOLE commit to NOTRUN — the readable sibling's innerHTML XSS LANDED (BL-182 all-or-nothing break): $(grep -E 'SAST NOT ENFORCED|could not materialize' "$TOPTMP/oD" | head -1)"
        elif not_enforced "$TOPTMP/oD"; then
          skip_ "T-partial-vuln-still-blocks" "scanner did not run (registry unreachable?) — blocking UNPROVEN here"
        else
          fail_ "T-partial-vuln-still-blocks" "the readable sibling's XSS COMMITTED: $(grep -E '\[OK\]|\[BLOCKED\]' "$TOPTMP/oD" | head -1)"
        fi
      elif ! grep -q "\[BLOCKED\]" "$TOPTMP/oD"; then
        fail_ "T-partial-vuln-still-blocks" "refused but without [BLOCKED] (wrong reason): $(tail -3 "$TOPTMP/oD" | tr '\n' '|')"
      elif [ "$H0" != "$H1" ]; then
        fail_ "T-partial-vuln-still-blocks" "non-zero exit but HEAD MOVED"
      elif ! grep -q 'app\.ts' "$TOPTMP/oD"; then
        fail_ "T-partial-vuln-still-blocks" "blocked, but the finding did not name the real path app.ts"
      elif ! grep -qxF "    - $LONG_NAME" "$TOPTMP/oD"; then
        fail_ "T-partial-vuln-still-blocks" "blocked correctly, but the unreadable entry was never NAMED — a blocked commit still owes the operator its coverage gap (BL-182)"
      else
        pass "T-partial-vuln-still-blocks: an unreadable entry no longer blinds its siblings — the readable sibling's XSS is REFUSED and the coverage gap is named (BL-182)"
      fi
    fi
  fi

  # ── T-gitlink-not-counted-unread (BL-182 x BL-132-GITLINK-SKIP) ────────────
  # The two per-entry `continue`s in the loop look identical and mean OPPOSITE things,
  # so the distinction needs a pin of its own. A GITLINK is not content: it is skipped
  # with NO trace and costs the commit nothing. An UNREADABLE entry IS content we owe a
  # scan of: it forfeits the whole commit's [OK] receipt and is reported by name.
  # Collapsing the two — in either direction — is a real hazard: treat a gitlink as
  # unread and every submodule commit loses its receipt (operators stop reading the
  # warning); treat an unreadable blob as a gitlink and an unscanned file buys a
  # clean-looking commit, which is the silent-success class itself.
  # SCOPE, STATED PRECISELY (R-WPC2-1 refuted the earlier "pins BOTH directions" claim):
  # this case pins the ACCEPT direction of the mode predicate — a real mode-160000 entry
  # is skipped untraced — and pins that an unreadable entry beside it still forfeits the
  # receipt. It does NOT reach the predicate's REJECT direction, because its unreadable
  # entry ($LONG_NAME) is a HEALTHY blob: `git cat-file -t :0:$LONG_NAME` returns `blob`,
  # so the non-blob branch that holds the mode test is never entered and widening that
  # test to a blanket skip leaves this case GREEN. T-nonblob-nongitlink-forfeits-receipt
  # below carries the REJECT direction; the two are a pair, not a duplicate.
  # Hermetic: the gitlink is a `--cacheinfo 160000` index row, so no submodule (and
  # certainly no remote) is needed to produce one.
  echo "=== T-gitlink-not-counted-unread ==="
  RG2="$TOPTMP/mixedskip"
  if ! mk_repo "$RG2" "$EMITTED"; then
    fail_ "T-gitlink-not-counted-unread" "repo setup failed"
  elif ! stage_index_only "$RG2" "$LONG_NAME" "$XSS_TS"; then
    skip_ "T-gitlink-not-counted-unread" "could not add the long-component path to the index — generator UNAVAILABLE here"
  else
    RG2_SEED="$( cd "$RG2" && git rev-parse HEAD )"
    ( cd "$RG2" && git update-index --add --cacheinfo "160000,$RG2_SEED,sub" ) >/dev/null 2>&1
    printf '%s\n' "$SAFE_TS" > "$RG2/app.ts"
    ( cd "$RG2" && git add app.ts ) >/dev/null 2>&1
    RG2_MODE="$( cd "$RG2" && git ls-files -s -- ":(literal)sub" 2>/dev/null | awk 'NR==1{print $1}' )"
    RG2_N="$( cd "$RG2" && git diff --cached --name-only --diff-filter=ACMR | wc -l | tr -d '[:space:]' )"
    if [ "$RG2_MODE" != "160000" ] || [ "$RG2_N" != "3" ]; then
      skip_ "T-gitlink-not-counted-unread" "fixture invalid (sub mode='$RG2_MODE' want 160000, staged=$RG2_N want 3) — the gitlink/unreadable distinction is UNPROVEN here"
    else
      H0="$(head_of "$RG2")"
      if ( cd "$RG2" && git commit -m "feat: gitlink plus unreadable plus clean" ) >"$TOPTMP/oG" 2>&1; then V=COMMITTED; else V=REFUSED; fi
      H1="$(head_of "$RG2")"
      if grep -qF 'semgrep could not complete' "$TOPTMP/oG"; then
        skip_ "T-gitlink-not-counted-unread" "semgrep itself failed (registry unreachable?) — the clean-but-partial arm was never exercised"
      elif grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/oG"; then
        fail_ "T-gitlink-not-counted-unread" "an UNEARNED [OK] over a commit with one unreadable entry: $(grep -F '[OK] semgrep: SAST ran' "$TOPTMP/oG" | head -1)"
      elif ! grep -qxF "    - $LONG_NAME" "$TOPTMP/oG"; then
        fail_ "T-gitlink-not-counted-unread" "the unreadable entry was not NAMED alongside a staged gitlink (BL-182); log tail: $(tail -4 "$TOPTMP/oG" | cut -c1-90 | tr '\n' '|')"
      elif grep -qxF "    - sub" "$TOPTMP/oG"; then
        fail_ "T-gitlink-not-counted-unread" "the staged GITLINK was reported as an entry that could not be READ — a gitlink is not content, and counting it as lost coverage would strip the receipt from every routine submodule commit"
      elif [ "$V" != "COMMITTED" ] || [ "$H0" = "$H1" ]; then
        fail_ "T-gitlink-not-counted-unread" "must WARN, never block (BL-112 contract); verdict=$V moved=$([ "$H0" != "$H1" ] && echo YES || echo NO)"
      else
        pass "T-gitlink-not-counted-unread: a staged gitlink is skipped WITHOUT being counted as lost coverage, while the unreadable blob beside it still forfeits the receipt and is named (BL-182 x BL-132-GITLINK-SKIP)"
      fi
    fi
  fi
fi

# ── T-nonblob-nongitlink-forfeits-receipt (R-WPC2-1) ─────────────────────────
# THE REJECT DIRECTION OF THE MODE PREDICATE, which nothing else in this suite reaches.
# T-gitlink-not-counted-unread above pins the ACCEPT direction (mode 160000 => skip with
# no trace) and pins that a LONG_NAME entry still forfeits the receipt — but that entry
# is a HEALTHY blob whose materialization fails at the WRITE site, so it never enters
# the non-blob branch and the mode test is invisible to it. Widening the predicate to
# the blanket "unreadable => skip" that # BL-132-GITLINK-SKIP explicitly forbids was
# therefore INVISIBLE to every lane: the whole suite stayed 25/0 under it, and the
# commit landed carrying an unscanned staged entry behind an unearned [OK] receipt —
# the exact silent-success class BL-182 exists to retire (R-WPC2-1, reproduced A/B
# through the real emitter, the real .git/hooks/pre-commit and a real `git commit`).
# The fixture is a TREE object staged at index mode 100644: ls-files reports
# `100644 <sha> 0 weird.ts` so the 160000 test must REJECT it, while
# `git cat-file -t :0:weird.ts` says `tree` so it is genuinely not scannable content.
# It must therefore be recorded as unread, forfeit the receipt, and be NAMED.
echo "=== T-nonblob-nongitlink-forfeits-receipt ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-nonblob-nongitlink-forfeits-receipt" "semgrep ABSENT — skip, not pass"
else
  RW="$TOPTMP/nonblob"
  if ! mk_repo "$RW" "$EMITTED"; then
    fail_ "T-nonblob-nongitlink-forfeits-receipt" "repo setup failed"
  elif ! stage_tree_at_blob_mode "$RW" "weird.ts"; then
    skip_ "T-nonblob-nongitlink-forfeits-receipt" "could not stage a tree object at blob mode — generator UNAVAILABLE here"
  else
    printf '%s\n' "$SAFE_TS" > "$RW/app.ts"
    ( cd "$RW" && git add app.ts ) >/dev/null 2>&1
    RW_MODE="$( cd "$RW" && git ls-files -s -- ":(literal)weird.ts" 2>/dev/null | awk 'NR==1{print $1}' )"
    RW_TYPE="$( cd "$RW" && git cat-file -t ":0:weird.ts" 2>/dev/null )"
    RW_N="$( cd "$RW" && git diff --cached --name-only --diff-filter=ACMRT | wc -l | tr -d '[:space:]' )"
    # All three halves of the shape are re-probed: a fixture that degraded into a
    # gitlink (mode 160000) would exercise the ACCEPT direction instead, and one that
    # degraded into a real blob would never enter the non-blob branch at all. Either
    # way the case would pass while proving nothing, so it LOUD-SKIPs.
    if [ "$RW_MODE" = "160000" ] || [ "$RW_TYPE" = "blob" ] || [ "$RW_N" != "2" ]; then
      skip_ "T-nonblob-nongitlink-forfeits-receipt" "fixture invalid (mode='$RW_MODE' must NOT be 160000, index type='$RW_TYPE' must NOT be blob, staged=$RW_N want 2) — the REJECT direction of the mode predicate is UNPROVEN here"
    else
      H0="$(head_of "$RW")"
      if ( cd "$RW" && git commit -m "feat: non-blob non-gitlink entry beside a clean sibling" ) >"$TOPTMP/oW" 2>&1; then V=COMMITTED; else V=REFUSED; fi
      H1="$(head_of "$RW")"
      if grep -qF 'semgrep could not complete' "$TOPTMP/oW"; then
        skip_ "T-nonblob-nongitlink-forfeits-receipt" "semgrep itself failed (registry unreachable?) — the CLEAN-but-partial arm was never exercised, so this case would pass on the tool-failure arm instead"
      elif grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/oW"; then
        fail_ "T-nonblob-nongitlink-forfeits-receipt" "a non-blob, NON-GITLINK staged entry was skipped with NO trace and the clean sibling bought an UNEARNED [OK] — the mode-gated skip has been widened into the blanket 'unreadable => skip' # BL-132-GITLINK-SKIP forbids (R-WPC2-1): $(grep -F '[OK] semgrep: SAST ran' "$TOPTMP/oW" | head -1)"
      elif ! not_enforced "$TOPTMP/oW"; then
        fail_ "T-nonblob-nongitlink-forfeits-receipt" "partial coverage produced no loud NOTRUN — the operator is told nothing: $(tail -5 "$TOPTMP/oW" | tr '\n' '|')"
      elif ! grep -qxF "    - weird.ts" "$TOPTMP/oW"; then
        fail_ "T-nonblob-nongitlink-forfeits-receipt" "the NOTRUN did not NAME the non-blob entry it could not read (# BL-182-NAME-THE-ENTRY); log tail: $(tail -4 "$TOPTMP/oW" | cut -c1-90 | tr '\n' '|')"
      elif [ "$V" != "COMMITTED" ] || [ "$H0" = "$H1" ]; then
        fail_ "T-nonblob-nongitlink-forfeits-receipt" "an unreadable entry must WARN, never block (BL-112 contract); verdict=$V moved=$([ "$H0" != "$H1" ] && echo YES || echo NO)"
      else
        pass "T-nonblob-nongitlink-forfeits-receipt: a staged entry that is neither blob nor gitlink forfeits the commit's [OK] receipt and is NAMED — the skip stays gated on index mode 160000 (R-WPC2-1)"
      fi
    fi
  fi
fi

# ── T-pathmax-sibling-caught (BL-182 original trigger) ───────────────────────
# The filed trigger: a repo-relative path long enough that `mktemp -d` + the BL-178
# `/<n>/` segment + the path exceeds PATH_MAX. Legal in the worktree and in the index,
# unrepresentable as a materialization destination. Measured on the filing host at
# repo-relative length 991: main BLOCKED the sibling, the PR head landed it. This case
# fires at the DIRNAME/MKDIR site (the LONG_NAME cases fire at the WRITE site), so both
# per-entry recovery points are covered.
echo "=== T-pathmax-sibling-caught ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-pathmax-sibling-caught" "semgrep ABSENT — skip, not pass"
elif temp_tree_can_hold_path "$LONG_PATH"; then
  skip_ "T-pathmax-sibling-caught" "this host CAN express a ${#LONG_PATH}-byte repo-relative path under a mktemp -d root plus the per-index segment (short temp root / large PATH_MAX) — the overflow does not fire and the case would pass vacuously"
else
  RE="$TOPTMP/pathmax"
  if ! mk_repo "$RE" "$EMITTED"; then
    fail_ "T-pathmax-sibling-caught" "repo setup failed"
  elif ! stage_index_only "$RE" "$LONG_PATH" "$SAFE_TS"; then
    skip_ "T-pathmax-sibling-caught" "could not add a ${#LONG_PATH}-byte path to the index — generator UNAVAILABLE here"
  else
    printf '%s\n' "$XSS_TS" > "$RE/app.ts"
    ( cd "$RE" && git add app.ts ) >/dev/null 2>&1
    RE_N="$( cd "$RE" && git diff --cached --name-only --diff-filter=ACMR | wc -l | tr -d '[:space:]' )"
    if [ "$RE_N" != "2" ]; then
      skip_ "T-pathmax-sibling-caught" "fixture invalid (staged=$RE_N want 2) — PATH_MAX regression UNPROVEN here"
    else
      H0="$(head_of "$RE")"
      if ( cd "$RE" && git commit -m "feat: overlong path plus sibling" ) >"$TOPTMP/oE" 2>&1; then V=COMMITTED; else V=REFUSED; fi
      H1="$(head_of "$RE")"
      if [ "$V" = "COMMITTED" ]; then
        if grep -qF 'semgrep could not complete' "$TOPTMP/oE"; then
          skip_ "T-pathmax-sibling-caught" "semgrep itself failed (registry unreachable?) — blocking UNPROVEN here; checked BEFORE the abort verdict so a tool failure is not misreported as the BL-182 regression"
        elif not_enforced "$TOPTMP/oE"; then
          fail_ "T-pathmax-sibling-caught" "the overlong staged path aborted materialization and the whole commit went NOTRUN — the sibling app.ts innerHTML XSS LANDED (BL-182): $(grep -E 'SAST NOT ENFORCED|could not materialize' "$TOPTMP/oE" | head -1)"
        else
          fail_ "T-pathmax-sibling-caught" "the sibling XSS COMMITTED: $(grep -E '\[OK\]|\[BLOCKED\]' "$TOPTMP/oE" | head -1)"
        fi
      elif ! grep -q "\[BLOCKED\]" "$TOPTMP/oE"; then
        fail_ "T-pathmax-sibling-caught" "refused but without [BLOCKED] (wrong reason): $(tail -3 "$TOPTMP/oE" | tr '\n' '|')"
      elif [ "$H0" != "$H1" ]; then
        fail_ "T-pathmax-sibling-caught" "non-zero exit but HEAD MOVED"
      elif ! grep -q 'app\.ts' "$TOPTMP/oE"; then
        fail_ "T-pathmax-sibling-caught" "blocked, but the sibling app.ts was not named"
      elif grep -q '^dirname:' "$TOPTMP/oE" || grep -q 'File name too long' "$TOPTMP/oE"; then
        fail_ "T-pathmax-sibling-caught" "a raw \`dirname\` diagnostic leaked into the operator's commit transcript — the 2>/dev/null sits on mkdir, but the command substitution runs FIRST with unredirected stderr: $(grep -m1 -E '^dirname:|File name too long' "$TOPTMP/oE" | cut -c1-120)"
      elif ! grep -qxF "    - $LONG_PATH" "$TOPTMP/oE"; then
        fail_ "T-pathmax-sibling-caught" "blocked correctly, but the overlong entry was never NAMED as unscanned (BL-182)"
      else
        pass "T-pathmax-sibling-caught: a PATH_MAX-overflowing staged path no longer blinds its siblings — the sibling XSS is REFUSED, the gap is named, no raw tool diagnostic leaks (BL-182)"
      fi
    fi
  fi
fi

# ── T-mutation-content-guard (F2: empty/partial materialize -> loud NOTRUN) ───
# The F2 size check turns an empty/partial materialization into a LOUD NOTRUN
# instead of scanning an empty file and passing [OK]. The GREEN direction fires
# BEFORE semgrep runs (no registry needed): force the materialization to write
# empty/partial dests and the content check must NOTRUN. The RED direction removes
# F2 so the empty scan passes [OK] silently (needs the registry, LOUD-SKIP if down).
#
# ANCHOR COUPLING — the two _idx_mutate anchors below are the EXACT emitted
# materialization line, matched literally (awk index(), `exit 3` unless it appears
# EXACTLY once). They are therefore coupled to # BL-132-STAGE0-REF: changing the
# emitted index reference (`:$soif_p` -> `:0:$soif_p`) makes this case report
# MIS-TARGETED rather than pass vacuously, and the anchor must be retargeted in
# lockstep. Keep the anchor a FULL literal — never relax it to a prefix that would
# match both the stage-explicit and the bare form, because the whole point of the
# exactly-once check is to notice when the surface it attacks has moved.
#   Second coupling, added with # BL-182-PER-ENTRY-SKIP: the materialization line is
#   now wrapped in a brace group (`{ … ; } 2>/dev/null`) so the SHELL's own "cannot
#   create" diagnostic cannot leak past the redirect. The literal above is still a
#   SUBSTRING of that line, so both mutants still splice cleanly — but if the group
#   is ever reshaped so the literal no longer appears verbatim, the exactly-once
#   check fires instead of the case quietly proving nothing.
echo "=== T-mutation-content-guard ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-mutation-content-guard" "semgrep ABSENT — skip, not pass"
else
  _idx_mutate() { awk -v old="$2" -v new="$3" '{p=index($0,old); if(p>0){$0=substr($0,1,p-1) new substr($0,p+length(old)); c++} print} END{if(c!=1) exit 3}' "$1"; }
  _cg_commit() {  # <hookfile> <log>
    local d; d="$(mktemp -d)"
    mk_repo "$d" "$1" >/dev/null 2>&1 || { rm -rf "$d"; return 9; }
    printf '%s\n' "$XSS_TS" > "$d/app.ts"
    ( cd "$d" && git add app.ts && git commit -m "feat: app" ) >"$2" 2>&1 || true
    rm -rf "$d"
  }
  cg_setup=1
  MEMPTY="$TOPTMP/cg-empty"
  _idx_mutate "$EMITTED" 'git cat-file blob ":0:$soif_p" > "$soif_idx_dest"' ': > "$soif_idx_dest"' > "$MEMPTY" || cg_setup=0
  MPART="$TOPTMP/cg-part"
  _idx_mutate "$EMITTED" 'git cat-file blob ":0:$soif_p" > "$soif_idx_dest"' 'git cat-file blob ":0:$soif_p" | head -c 3 > "$soif_idx_dest"' > "$MPART" || cg_setup=0
  # F2-removed variant of M-empty: drop exactly the three F2 CHECK lines (keep the
  # soif_idx_files+= collection), so the empty dest is scanned and passes [OK].
  #   COUNTED, NOT BEST-EFFORT — and retargeted in lockstep with # BL-182-PER-ENTRY-SKIP,
  #   which rewrote the conditional's tail from `soif_idx_ok=0; break` to the per-entry
  #   `soif_idx_unread+=(...); continue`. The old pattern keyed on that tail; left
  #   unretargeted it would silently stop matching, the two ASSIGNMENTS would still be
  #   dropped, and the surviving conditional would reference an unset variable under
  #   `set -u` — aborting the hook and REFUSING the commit for a reason that has
  #   nothing to do with F2. That looks like a working test and proves nothing, so
  #   each of the three lines must match EXACTLY ONCE or this reports MIS-TARGETED.
  MEMPTY_NOF2="$TOPTMP/cg-empty-nof2"
  cg_f2drop=1
  awk '
    /soif_idx_want=\$\(git cat-file -s/            { w++; next }
    /soif_idx_got=\$\(wc -c/                       { g++; next }
    /\[ "\$soif_idx_got" != "\$soif_idx_want" \]/  { c++; next }
    { print }
    END { if (w != 1 || g != 1 || c != 1) exit 3 }
  ' "$MEMPTY" > "$MEMPTY_NOF2" || cg_f2drop=0
  if [ "$cg_setup" != "1" ]; then
    fail_ "T-mutation-content-guard" "MIS-TARGETED — the materialization anchor is not present exactly once"
  elif [ "$cg_f2drop" != "1" ]; then
    fail_ "T-mutation-content-guard" "MIS-TARGETED — the three F2 content-check lines are not each present exactly once in the emitted hook (the guard moved; retarget this removal in lockstep)"
  elif ! bash -n "$MEMPTY" 2>/dev/null || ! bash -n "$MPART" 2>/dev/null || ! bash -n "$MEMPTY_NOF2" 2>/dev/null; then
    fail_ "T-mutation-content-guard" "a content-guard mutant has a syntax error — a broken mutant proves nothing"
  elif grep -qF 'soif_idx_want=' "$MEMPTY_NOF2"; then
    fail_ "T-mutation-content-guard" "the F2-removal awk did not drop the content-check lines"
  else
    _cg_commit "$MEMPTY" "$TOPTMP/cg1"
    _cg_commit "$MPART" "$TOPTMP/cg2"
    _cg_commit "$MEMPTY_NOF2" "$TOPTMP/cg3"
    # THE NAMING ASSERTION IS DELIBERATE (R-WPC-2). The F2 size-mismatch point is one of
    # the four per-entry recovery points # BL-182-PER-ENTRY-SKIP introduced, and its
    # `soif_idx_unread` RECORDING — as opposed to a bare `continue` — was pinned only
    # STRUCTURALLY, by the exactly-once counter above. A recovery point that skips the
    # entry WITHOUT recording it produces the worst outcome in this whole arm: coverage
    # is lost and nothing forfeits the receipt. `not_enforced` alone cannot see that (a
    # single-entry fixture NOTRUNs either way, via # BL-132-EMPTY-TARGETS), so each F2
    # arm additionally asserts the entry is NAMED, exact-line, by the unread report.
    if ! not_enforced "$TOPTMP/cg1"; then
      fail_ "T-mutation-content-guard" "M-empty materialize did NOT go loud NOTRUN with F2 present — F2 is not catching the empty dest: $(tail -3 "$TOPTMP/cg1" | tr '\n' '|')"
    elif ! grep -qxF "    - app.ts" "$TOPTMP/cg1"; then
      fail_ "T-mutation-content-guard" "M-empty materialize NOTRUNed but never NAMED app.ts — the F2 recovery point skipped the entry without recording it in soif_idx_unread, so a multi-entry commit would have lost that file's coverage and still earned its [OK] (R-WPC-2): $(tail -4 "$TOPTMP/cg1" | tr '\n' '|')"
    elif ! not_enforced "$TOPTMP/cg2"; then
      fail_ "T-mutation-content-guard" "M-partial materialize did NOT go loud NOTRUN with F2 present: $(tail -3 "$TOPTMP/cg2" | tr '\n' '|')"
    elif ! grep -qxF "    - app.ts" "$TOPTMP/cg2"; then
      fail_ "T-mutation-content-guard" "M-partial materialize NOTRUNed but never NAMED app.ts — see the M-empty arm above (R-WPC-2): $(tail -4 "$TOPTMP/cg2" | tr '\n' '|')"
    elif grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/cg3"; then
      pass "T-mutation-content-guard: empty+partial materialize -> loud NOTRUN WITH F2 (GREEN); F2 removed -> the empty scan passes [OK] silently (RED) — F2 is load-bearing"
    elif not_enforced "$TOPTMP/cg3"; then
      skip_ "T-mutation-content-guard" "F2 GREEN held (empty+partial -> NOTRUN); the F2-removed RED is unprovable here (scanner did not run on the empty-scan variant — registry unreachable?)"
    else
      fail_ "T-mutation-content-guard" "F2-removed empty materialize neither passed [OK] nor NOTRUN: $(tail -3 "$TOPTMP/cg3" | tr '\n' '|')"
    fi
  fi
fi

# ── T-mutation-index-scan ────────────────────────────────────────────────────
# Revert exactly the index-scan: point semgrep back at the worktree paths
# ("${soif_staged[@]}") instead of the EXPLICIT materialized index files. The
# staged-vuln/clean-worktree commit must then LAND (RED) — the clean worktree scans
# clean. Restore the index-files target and the same commit is REFUSED (GREEN).
# awk literal index()/substr() replace (not sed): the index-files target expansion
# ${soif_idx_files[@]+"${soif_idx_files[@]}"} is regex-hostile, so match it literally.
echo "=== T-mutation-index-scan ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-mutation-index-scan" "semgrep ABSENT — mutation UNPROVEN (skip, not pass)"
else
  MUT="$TOPTMP/mut-hook"
  MUT_MIS=0
  awk -v old='--severity=ERROR --error ${soif_idx_files[@]+"${soif_idx_files[@]}"}' \
      -v new='--severity=ERROR --error "${soif_staged[@]}"' '
    { p=index($0, old); if(p>0){ $0=substr($0,1,p-1) new substr($0,p+length(old)); c++ } print }
    END { if(c!=1) exit 3 }
  ' "$EMITTED" > "$MUT" || MUT_MIS=1
  if [ "$MUT_MIS" = "1" ]; then
    fail_ "T-mutation-index-scan" "MIS-TARGETED — the index-files scan-target anchor is not present exactly once in the emitted hook"
  elif ! grep -qF '# BL-132-INDEX-SCAN' "$MUT"; then
    fail_ "T-mutation-index-scan" "mutation removed the marker — it must attack BEHAVIOUR, not the marker"
  elif ! bash -n "$MUT" 2>/dev/null; then
    fail_ "T-mutation-index-scan" "mutated hook has a syntax error — a broken mutant proves nothing"
  else
    RM="$TOPTMP/mut-repo"
    if ! mk_repo "$RM" "$MUT"; then
      fail_ "T-mutation-index-scan" "mut repo setup failed"
    else
      H0="$(head_of "$RM")"
      RED="$(stage_then_overwrite "$RM" "$XSS_TS" "$SAFE_TS" "$TOPTMP/red")"
      # restore: same fixture, real (temp-tree) hook.
      RG="$TOPTMP/mut-repo-green"
      mk_repo "$RG" "$EMITTED"
      GREEN="$(stage_then_overwrite "$RG" "$XSS_TS" "$SAFE_TS" "$TOPTMP/green")"
      if not_enforced "$TOPTMP/red" || not_enforced "$TOPTMP/green"; then
        skip_ "T-mutation-index-scan" "scanner did not run (registry unreachable?) — mutation direction unprovable here"
      elif [ "$RED" = "COMMITTED" ] && [ "$GREEN" = "REFUSED" ]; then
        pass "T-mutation-index-scan: worktree-scan LANDS the staged vuln (RED); index-scan REFUSES it (GREEN)"
      else
        fail_ "T-mutation-index-scan" "expected RED=COMMITTED/GREEN=REFUSED; got RED=$RED GREEN=$GREEN; red: $(tail -3 "$TOPTMP/red" | tr '\n' '|'); green: $(tail -3 "$TOPTMP/green" | tr '\n' '|')"
      fi
    fi
  fi
fi

# ── mutation helpers (BL-179 / BL-182) ───────────────────────────────────────
# Literal awk index()/substr() replacement with an EXPECTED OCCURRENCE COUNT. The
# count is the mis-target detector: if the surface a mutation attacks has moved or
# multiplied, the mutant is reported MIS-TARGETED instead of silently proving nothing.
# _mut_n <src> <dst> <literal-old> <literal-new> <expected-count>
# The scan advances past each replacement rather than re-scanning the rewritten line,
# so a <literal-new> that happens to CONTAIN <literal-old> cannot spin forever — a
# mutation helper that hangs is worse than one that mis-targets, because a hang has no
# verdict at all.
_mut_n() {
  awk -v old="$3" -v new="$4" -v want="$5" '
    { out = ""; rest = $0
      while ((p = index(rest, old)) > 0) {
        out = out substr(rest, 1, p-1) new
        rest = substr(rest, p + length(old))
        c++
      }
      print out rest }
    END { if (c != want) exit 3 }
  ' "$1" > "$2"
}

# ── T-mutation-rename-filter (BL-179 proof (a)) ──────────────────────────────
# Drop exactly the R from the staged-target filter, ACMRT -> ACMT. The rename-and-edit
# commit's destination is then never scanned and its XSS LANDS (RED); restore ACMRT and
# the same commit is REFUSED with a [BLOCKED] naming the destination (GREEN).
#   ONE LETTER AT A TIME, deliberately: this case owns R, T-mutation-typechange-filter
#   owns T and T-mutation-delete-filter owns D. A mutant that dropped BOTH R and T would
#   still go RED here while proving nothing about which letter carried the weight.
#   ANCHOR COUPLING: the literal below carries the FULL filter value, so widening
#   # BL-179-STAGED-FILTER by another letter makes _mut_n's exactly-once count fail and
#   this case reports MIS-TARGETED rather than silently mutating nothing. That is the
#   designed behaviour — retarget all three filter anchors in lockstep when it fires.
#   THE RED IS "IT LANDS", NOT "IT IS SILENT". BL-179 had two halves — the filter and
#   the missing `else` — and this mutation reverts only the first, so the surviving
#   # BL-179-EMPTY-STAGED arm still prints a loud NOTRUN over the empty target set. The
#   historical TOTAL silence is pinned separately: by T-rename-edit-scanned's
#   any_sast_line() assertion (watched RED against the pre-fix lib) and by
#   T-mutation-empty-staged-silence below, which attacks the other half directly.
echo "=== T-mutation-rename-filter ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-mutation-rename-filter" "semgrep ABSENT — mutation UNPROVEN (skip, not pass)"
else
  MRF="$TOPTMP/mut-acm"
  if ! _mut_n "$EMITTED" "$MRF" '--diff-filter=ACMRT -z' '--diff-filter=ACMT -z' 1; then
    fail_ "T-mutation-rename-filter" "MIS-TARGETED — the SAST staged-read filter '--diff-filter=ACMRT -z' is not present exactly once in the emitted hook"
  elif ! bash -n "$MRF" 2>/dev/null; then
    fail_ "T-mutation-rename-filter" "mutated hook has a syntax error — a broken mutant proves nothing"
  else
    _ren_commit() {  # <hookfile> <log> -> COMMITTED|REFUSED
      local d; d="$(mktemp -d)"
      mk_repo_seeded "$d" "$1" old.ts "$REN_SAFE" >/dev/null 2>&1 || { rm -rf "$d"; echo SETUPFAIL; return; }
      ( cd "$d" && git mv old.ts new.ts ) >/dev/null 2>&1
      printf '%s\n' "$REN_VULN" > "$d/new.ts"
      ( cd "$d" && git add -- new.ts ) >/dev/null 2>&1   # destination only: see T-rename-edit-scanned
      if ! ( cd "$d" && git cat-file blob ":0:new.ts" 2>/dev/null ) | grep -q 'innerHTML'; then
        rm -rf "$d"; echo SETUPFAIL; return
      fi
      if ( cd "$d" && git commit -m "refactor: rename and harden render" ) >"$2" 2>&1; then echo COMMITTED; else echo REFUSED; fi
      rm -rf "$d"
    }
    MRF_RED="$(_ren_commit "$MRF" "$TOPTMP/mrf-red")"
    MRF_GRN="$(_ren_commit "$EMITTED" "$TOPTMP/mrf-green")"
    if [ "$MRF_RED" = "SETUPFAIL" ] || [ "$MRF_GRN" = "SETUPFAIL" ]; then
      fail_ "T-mutation-rename-filter" "mutation fixture setup failed"
    elif not_enforced "$TOPTMP/mrf-green"; then
      skip_ "T-mutation-rename-filter" "scanner did not run on the GREEN side (registry unreachable?) — mutation direction unprovable here"
    elif [ "$MRF_RED" = "COMMITTED" ] && ! grep -qF '[BLOCKED]' "$TOPTMP/mrf-red" \
         && [ "$MRF_GRN" = "REFUSED" ] && grep -qF '[BLOCKED]' "$TOPTMP/mrf-green"; then
      pass "T-mutation-rename-filter: ACMT leaves the renamed destination unscanned and LANDS its XSS (RED); ACMRT REFUSES it (GREEN) — the R in the filter is load-bearing"
    else
      fail_ "T-mutation-rename-filter" "expected RED=COMMITTED+no-[BLOCKED] / GREEN=REFUSED+[BLOCKED]; got RED=$MRF_RED (blocked=$(grep -cF '[BLOCKED]' "$TOPTMP/mrf-red")) GREEN=$MRF_GRN; red: $(tail -3 "$TOPTMP/mrf-red" | tr '\n' '|'); green: $(tail -3 "$TOPTMP/mrf-green" | tr '\n' '|')"
    fi
  fi

fi

# ── T-mutation-typechange-filter (R-WPC-1, the T is load-bearing) ────────────
# Drop exactly the T from the staged-target filter, ACMRT -> ACMR — i.e. revert to the
# value this remediation replaced. The staged TYPE CHANGE is then dropped from the
# TARGET SET before the materialization loop ever runs, so soif_idx_unread stays EMPTY,
# # BL-182-NO-UNEARNED-RECEIPT cannot fire, and the clean sibling buys an `[OK] … ran on
# N staged file(s)` receipt while the dropped entry's innerHTML sink LANDS (RED).
# Restore ACMRT and the same commit is REFUSED with a [BLOCKED] naming link.ts (GREEN).
#   THE RED ASSERTION IS THE RECEIPT, NOT MERELY THE LANDING. "It committed" alone would
#   also be satisfied by a loud NOTRUN, which is honest; the defect being pinned is the
#   false [OK] over a set the FILTER truncated, so the RED requires that receipt present.
echo "=== T-mutation-typechange-filter ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-mutation-typechange-filter" "semgrep ABSENT — mutation UNPROVEN (skip, not pass)"
else
  MTF="$TOPTMP/mut-acmr"
  _tc_commit() {  # <hookfile> <log> -> COMMITTED|REFUSED|SETUPFAIL|NOGEN
    local d; d="$(mktemp -d)"
    mk_repo_typechange "$d" "$1" >/dev/null 2>&1 || { rm -rf "$d"; echo NOGEN; return; }
    rm -f "$d/link.ts"
    printf '%s\n' "$XSS_TS"  > "$d/link.ts"
    printf '%s\n' "$SAFE_TS" > "$d/app.ts"
    ( cd "$d" && git add -- link.ts app.ts ) >/dev/null 2>&1
    if ! ( cd "$d" && git diff --cached --name-status | grep -q '^T' ); then rm -rf "$d"; echo NOGEN; return; fi
    if ! ( cd "$d" && git cat-file blob ":0:link.ts" 2>/dev/null ) | grep -q 'innerHTML'; then
      rm -rf "$d"; echo SETUPFAIL; return
    fi
    if ( cd "$d" && git commit -m "refactor: materialize the symlink" ) >"$2" 2>&1; then echo COMMITTED; else echo REFUSED; fi
    rm -rf "$d"
  }
  if ! _mut_n "$EMITTED" "$MTF" '--diff-filter=ACMRT -z' '--diff-filter=ACMR -z' 1; then
    fail_ "T-mutation-typechange-filter" "MIS-TARGETED — the SAST staged-read filter '--diff-filter=ACMRT -z' is not present exactly once in the emitted hook"
  elif ! bash -n "$MTF" 2>/dev/null; then
    fail_ "T-mutation-typechange-filter" "mutated hook has a syntax error — a broken mutant proves nothing"
  else
    MTF_RED="$(_tc_commit "$MTF" "$TOPTMP/mtf-red")"
    MTF_GRN="$(_tc_commit "$EMITTED" "$TOPTMP/mtf-green")"
    if [ "$MTF_RED" = "NOGEN" ] || [ "$MTF_GRN" = "NOGEN" ]; then
      skip_ "T-mutation-typechange-filter" "this host could not produce a status-T staged entry (no symlink support / core.symlinks=false) — mutation UNPROVEN here"
    elif [ "$MTF_RED" = "SETUPFAIL" ] || [ "$MTF_GRN" = "SETUPFAIL" ]; then
      fail_ "T-mutation-typechange-filter" "mutation fixture setup failed — the staged type-change blob carries no sink, so neither direction proves anything"
    elif not_enforced "$TOPTMP/mtf-green"; then
      skip_ "T-mutation-typechange-filter" "scanner did not run on the GREEN side (registry unreachable?) — mutation direction unprovable here"
    elif [ "$MTF_RED" = "COMMITTED" ] && grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/mtf-red" \
         && [ "$MTF_GRN" = "REFUSED" ] && grep -qF '[BLOCKED]' "$TOPTMP/mtf-green"; then
      pass "T-mutation-typechange-filter: ACMR truncates the target set and buys an UNEARNED [OK] while the type-change sink LANDS (RED); ACMRT REFUSES it (GREEN) — the T in the filter is load-bearing (R-WPC-1)"
    else
      fail_ "T-mutation-typechange-filter" "expected RED=COMMITTED+[OK]-receipt / GREEN=REFUSED+[BLOCKED]; got RED=$MTF_RED (ok=$(grep -cF '[OK] semgrep: SAST ran' "$TOPTMP/mtf-red")) GREEN=$MTF_GRN (blocked=$(grep -cF '[BLOCKED]' "$TOPTMP/mtf-green")); red: $(tail -3 "$TOPTMP/mtf-red" | tr '\n' '|'); green: $(tail -3 "$TOPTMP/mtf-green" | tr '\n' '|')"
    fi
  fi
fi

# ── T-mutation-delete-filter (BL-179, D must stay OUT) ───────────────────────
# Widen the filter with the BL-125 arm's D — the copy-paste this fix must NOT make.
# A deletion-only commit then hands the loop an index entry with no blob, and the arm
# reports it as unreadable content (RED: "could not materialize"). With ACMRT the same
# commit is honestly receipted and no phantom entry is ever manufactured (GREEN).
echo "=== T-mutation-delete-filter ==="
MDF="$TOPTMP/mut-acmdrt"
if ! _mut_n "$EMITTED" "$MDF" '--diff-filter=ACMRT -z' '--diff-filter=ACMDRT -z' 1; then
  fail_ "T-mutation-delete-filter" "MIS-TARGETED — the SAST staged-read filter is not present exactly once in the emitted hook"
elif ! bash -n "$MDF" 2>/dev/null; then
  fail_ "T-mutation-delete-filter" "mutated hook has a syntax error — a broken mutant proves nothing"
else
  MDF_RED="$(_del_commit "$MDF" "$TOPTMP/mdf-red")"
  MDF_GRN="$(_del_commit "$EMITTED" "$TOPTMP/mdf-green")"
  if [ "$MDF_RED" = "SETUPFAIL" ] || [ "$MDF_GRN" = "SETUPFAIL" ]; then
    fail_ "T-mutation-delete-filter" "mutation fixture setup failed"
  elif grep -qF 'could not materialize staged content' "$TOPTMP/mdf-red" \
       && ! grep -qF 'could not materialize staged content' "$TOPTMP/mdf-green" \
       && any_sast_line "$TOPTMP/mdf-green"; then
    pass "T-mutation-delete-filter: ACMDRT feeds a blob-less deleted path to the loop and reports lost coverage (RED); ACMRT never manufactures the phantom entry and still receipts the commit (GREEN)"
  else
    fail_ "T-mutation-delete-filter" "expected RED to report 'could not materialize' and GREEN not to; red_msg=$(grep -cF 'could not materialize' "$TOPTMP/mdf-red") green_msg=$(grep -cF 'could not materialize' "$TOPTMP/mdf-green") green_sast=$(grep -cE '\[OK\] semgrep: SAST ran|\[BLOCKED\] Semgrep|SAST NOT ENFORCED' "$TOPTMP/mdf-green"); red: $(tail -3 "$TOPTMP/mdf-red" | tr '\n' '|'); green: $(tail -3 "$TOPTMP/mdf-green" | tr '\n' '|')"
  fi
fi

# ── T-mutation-empty-staged-silence (BL-179, the other half of the defect) ────
# Attack # BL-179-EMPTY-STAGED directly: neuter the else-arm's report so an empty
# target set produces nothing again. A deletion-only commit must then be TOTALLY
# SILENT (RED) — no [OK], no [BLOCKED], no NOTRUN — and receipted once restored
# (GREEN). This is the assertion shape the original defect demanded: the absence of an
# absence, never the absence of a [BLOCKED]. Deliberately outside the semgrep guard:
# an empty target set never reaches the scanner, so the case is provable on any host.
echo "=== T-mutation-empty-staged-silence ==="
MES="$TOPTMP/mut-silence"
if ! _mut_n "$EMITTED" "$MES" 'soif_sast_not_enforced "no scannable staged file content' ': "silenced" #' 1; then
  fail_ "T-mutation-empty-staged-silence" "MIS-TARGETED — the empty-staged report is not present exactly once in the emitted hook"
elif ! bash -n "$MES" 2>/dev/null; then
  fail_ "T-mutation-empty-staged-silence" "mutated hook has a syntax error — a broken mutant proves nothing"
else
  MES_RED="$(_del_commit "$MES" "$TOPTMP/mes-red")"
  MES_GRN="$(_del_commit "$EMITTED" "$TOPTMP/mes-green")"
  if [ "$MES_RED" = "SETUPFAIL" ] || [ "$MES_GRN" = "SETUPFAIL" ]; then
    fail_ "T-mutation-empty-staged-silence" "mutation fixture setup failed"
  elif ! any_sast_line "$TOPTMP/mes-red" && any_sast_line "$TOPTMP/mes-green" \
       && [ "$MES_RED" = "COMMITTED" ] && [ "$MES_GRN" = "COMMITTED" ]; then
    pass "T-mutation-empty-staged-silence: neutering the empty-staged report makes the arm TOTALLY SILENT again (RED); restored, the same commit is receipted (GREEN) — the missing else was half of BL-179"
  else
    fail_ "T-mutation-empty-staged-silence" "expected RED=silent / GREEN=receipted, both COMMITTED; got RED=$MES_RED (sast_lines=$(grep -cE '\[OK\] semgrep: SAST ran|\[BLOCKED\] Semgrep|SAST NOT ENFORCED' "$TOPTMP/mes-red")) GREEN=$MES_GRN (sast_lines=$(grep -cE '\[OK\] semgrep: SAST ran|\[BLOCKED\] Semgrep|SAST NOT ENFORCED' "$TOPTMP/mes-green")); red: $(tail -3 "$TOPTMP/mes-red" | tr '\n' '|')"
  fi
fi

# ── T-mutation-partial-break (BL-182 proof (b)) ──────────────────────────────
# Restore the all-or-nothing behaviour: every per-entry recovery point becomes
# "throw away every sibling already materialized and stop". The partial+vuln fixture
# must then COMMIT the sibling's XSS (RED) — that is the regression the `break`
# actually caused. Per-entry recovery REFUSES it (GREEN).
echo "=== T-mutation-partial-break ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-mutation-partial-break" "semgrep ABSENT — mutation UNPROVEN (skip, not pass)"
  skip_ "T-mutation-partial-receipt" "semgrep ABSENT — mutation UNPROVEN (skip, not pass)"
elif fs_can_hold_name "$LONG_NAME"; then
  skip_ "T-mutation-partial-break" "this filesystem accepts a ${#LONG_NAME}-byte path component — the unreadable-entry generator does not fire here"
  skip_ "T-mutation-partial-receipt" "this filesystem accepts a ${#LONG_NAME}-byte path component — generator does not fire here"
else
  # <hookfile> <log> <sibling-content> -> COMMITTED|REFUSED, with an unreadable
  # long-component entry staged alongside the sibling.
  _partial_commit() {
    local d; d="$(mktemp -d)"
    mk_repo "$d" "$1" >/dev/null 2>&1 || { rm -rf "$d"; echo SETUPFAIL; return; }
    stage_index_only "$d" "$LONG_NAME" "$XSS_TS" || { rm -rf "$d"; echo SETUPFAIL; return; }
    printf '%s\n' "$3" > "$d/app.ts"
    ( cd "$d" && git add app.ts ) >/dev/null 2>&1
    if ( cd "$d" && git commit -m "feat: partial coverage fixture" ) >"$2" 2>&1; then echo COMMITTED; else echo REFUSED; fi
    rm -rf "$d"
  }
  MPB="$TOPTMP/mut-break"
  if ! _mut_n "$EMITTED" "$MPB" 'soif_idx_unread+=("$soif_p"); continue' 'soif_idx_files=(); break' 4; then
    fail_ "T-mutation-partial-break" "MIS-TARGETED — the per-entry recovery statement is not present exactly 4 times in the emitted hook (the recovery points moved; retarget this mutation in lockstep)"
  elif ! bash -n "$MPB" 2>/dev/null; then
    fail_ "T-mutation-partial-break" "mutated hook has a syntax error — a broken mutant proves nothing"
  else
    MPB_RED="$(_partial_commit "$MPB" "$TOPTMP/mpb-red" "$XSS_TS")"
    MPB_GRN="$(_partial_commit "$EMITTED" "$TOPTMP/mpb-green" "$XSS_TS")"
    if [ "$MPB_RED" = "SETUPFAIL" ] || [ "$MPB_GRN" = "SETUPFAIL" ]; then
      fail_ "T-mutation-partial-break" "mutation fixture setup failed"
    elif [ "$MPB_GRN" = "COMMITTED" ] && not_enforced "$TOPTMP/mpb-green"; then
      skip_ "T-mutation-partial-break" "scanner did not run on the GREEN side (registry unreachable?) — mutation direction unprovable here"
    elif [ "$MPB_RED" = "COMMITTED" ] && not_enforced "$TOPTMP/mpb-red" \
         && ! grep -qF '[BLOCKED]' "$TOPTMP/mpb-red" \
         && [ "$MPB_GRN" = "REFUSED" ] && grep -qF '[BLOCKED]' "$TOPTMP/mpb-green"; then
      # The RED side asserts a loud NOTRUN rather than one specific NOTRUN sentence:
      # the mutant discards soif_idx_files AND never records the entry, so it lands in
      # the zero-targets arm, not the could-not-materialize arm. The observable that
      # matters — and the one that is the actual regression — is that the whole commit
      # goes NOTRUN and the readable sibling's XSS LANDS.
      pass "T-mutation-partial-break: all-or-nothing recovery discards the readable sibling, NOTRUNs the whole commit and LANDS its XSS (RED); per-entry recovery REFUSES it (GREEN) — retiring the break is load-bearing"
    else
      fail_ "T-mutation-partial-break" "expected RED=COMMITTED+loud-NOTRUN+no-[BLOCKED] / GREEN=REFUSED+[BLOCKED]; got RED=$MPB_RED (notrun=$(grep -cF 'SAST NOT ENFORCED' "$TOPTMP/mpb-red") blocked=$(grep -cF '[BLOCKED]' "$TOPTMP/mpb-red")) GREEN=$MPB_GRN; red: $(tail -3 "$TOPTMP/mpb-red" | tr '\n' '|'); green: $(tail -3 "$TOPTMP/mpb-green" | tr '\n' '|')"
    fi
  fi

  # ── T-mutation-partial-receipt (BL-182 proof (c)) ──────────────────────────
  # Disarm exactly the no-unearned-receipt guard so a CLEAN-but-PARTIAL scan prints
  # the [OK] receipt. That is the silent-success class this arm exists to prevent, and
  # it must be RED. Restored, the same commit gets the loud partial NOTRUN (GREEN).
  echo "=== T-mutation-partial-receipt ==="
  MPR="$TOPTMP/mut-receipt"
  if ! _mut_n "$EMITTED" "$MPR" 'elif [ "${#soif_idx_unread[@]}" -gt 0 ]; then' 'elif false; then' 1; then
    fail_ "T-mutation-partial-receipt" "MIS-TARGETED — the clean-but-partial receipt guard is not present exactly once in the emitted hook"
  elif ! bash -n "$MPR" 2>/dev/null; then
    fail_ "T-mutation-partial-receipt" "mutated hook has a syntax error — a broken mutant proves nothing"
  else
    MPR_RED="$(_partial_commit "$MPR" "$TOPTMP/mpr-red" "$SAFE_TS")"
    MPR_GRN="$(_partial_commit "$EMITTED" "$TOPTMP/mpr-green" "$SAFE_TS")"
    if [ "$MPR_RED" = "SETUPFAIL" ] || [ "$MPR_GRN" = "SETUPFAIL" ]; then
      fail_ "T-mutation-partial-receipt" "mutation fixture setup failed"
    elif ! grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/mpr-red"; then
      skip_ "T-mutation-partial-receipt" "the disarmed mutant printed no [OK] either (scanner did not run — registry unreachable?) — the RED direction is unprovable here"
    elif grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/mpr-green"; then
      fail_ "T-mutation-partial-receipt" "the GREEN hook ALSO printed an [OK] receipt over a partial scan — the guard is not doing anything: $(grep -F '[OK] semgrep: SAST ran' "$TOPTMP/mpr-green" | head -1)"
    elif ! not_enforced "$TOPTMP/mpr-green"; then
      fail_ "T-mutation-partial-receipt" "the GREEN hook suppressed the receipt but printed no loud NOTRUN — silence is not honesty: $(tail -4 "$TOPTMP/mpr-green" | tr '\n' '|')"
    else
      pass "T-mutation-partial-receipt: disarming the guard buys an UNEARNED [OK] over a partial scan (RED); the guard routes it to the loud partial NOTRUN (GREEN)"
    fi
  fi
fi

# ── T-mutation-gitlink-mode-blanket (R-WPC2-1, the 160000 MODE test is load-bearing) ──
# Widen the skip's MODE test to a blanket match: `grep -q '^160000 '` -> `grep -q '^'`,
# i.e. "any entry ls-files knows about is skippable". That is precisely the blanket
# "unreadable => skip" # BL-132-GITLINK-SKIP forbids in prose, and prose is not a gate:
# the mutant records nothing in soif_idx_unread, so # BL-182-NO-UNEARNED-RECEIPT cannot
# fire and the clean sibling buys an `[OK] … ran on N staged file(s)` receipt while an
# unscanned staged entry LANDS (RED). Restored, the same commit forfeits the receipt and
# NAMES the entry (GREEN).
#   Deliberately outside the fs_can_hold_name guard: this generator is a --cacheinfo
#   index row, so unlike LONG_NAME/LONG_PATH it fires on every host and filesystem.
#   THE RED ASSERTION IS THE RECEIPT, NOT MERELY THE LANDING — the commit lands in BOTH
#   directions (an unreadable entry WARNs, never blocks), so "it committed" would be
#   satisfied by the honest arm too. The defect being pinned is the false [OK].
#   ANCHOR COUPLING: the literal carries the FULL predicate, so changing the mode test
#   makes _mut_n's exactly-once count fail and this case reports MIS-TARGETED rather
#   than silently mutating nothing. Retarget it in lockstep when that fires.
echo "=== T-mutation-gitlink-mode-blanket ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-mutation-gitlink-mode-blanket" "semgrep ABSENT — mutation UNPROVEN (skip, not pass)"
else
  MGM="$TOPTMP/mut-gitlink-mode"
  _nonblob_commit() {  # <hookfile> <log> -> COMMITTED|REFUSED|SETUPFAIL
    local d; d="$(mktemp -d)"
    mk_repo "$d" "$1" >/dev/null 2>&1 || { rm -rf "$d"; echo SETUPFAIL; return; }
    stage_tree_at_blob_mode "$d" "weird.ts" || { rm -rf "$d"; echo SETUPFAIL; return; }
    printf '%s\n' "$SAFE_TS" > "$d/app.ts"
    ( cd "$d" && git add app.ts ) >/dev/null 2>&1
    # Re-probe the shape inside the fixture: a degraded fixture (real blob, or a
    # gitlink) exercises a different branch and would prove nothing in either direction.
    if [ "$( cd "$d" && git cat-file -t ":0:weird.ts" 2>/dev/null )" = "blob" ] \
       || [ "$( cd "$d" && git ls-files -s -- ":(literal)weird.ts" 2>/dev/null | awk 'NR==1{print $1}' )" = "160000" ]; then
      rm -rf "$d"; echo SETUPFAIL; return
    fi
    if ( cd "$d" && git commit -m "feat: non-blob non-gitlink entry beside a clean sibling" ) >"$2" 2>&1; then echo COMMITTED; else echo REFUSED; fi
    rm -rf "$d"
  }
  if ! _mut_n "$EMITTED" "$MGM" "grep -q '^160000 '" "grep -q '^'" 1; then
    fail_ "T-mutation-gitlink-mode-blanket" "MIS-TARGETED — the gitlink MODE predicate is not present exactly once in the emitted hook (the skip's mode test moved or was widened; retarget this mutation in lockstep)"
  elif ! grep -qF '# BL-132-GITLINK-SKIP' "$MGM"; then
    fail_ "T-mutation-gitlink-mode-blanket" "mutation removed the marker — it must attack BEHAVIOUR, not the marker"
  elif ! bash -n "$MGM" 2>/dev/null; then
    fail_ "T-mutation-gitlink-mode-blanket" "mutated hook has a syntax error — a broken mutant proves nothing"
  else
    MGM_RED="$(_nonblob_commit "$MGM" "$TOPTMP/mgm-red")"
    MGM_GRN="$(_nonblob_commit "$EMITTED" "$TOPTMP/mgm-green")"
    if [ "$MGM_RED" = "SETUPFAIL" ] || [ "$MGM_GRN" = "SETUPFAIL" ]; then
      fail_ "T-mutation-gitlink-mode-blanket" "mutation fixture setup failed — no non-blob, non-gitlink staged entry, so neither direction proves anything"
    elif grep -qF 'semgrep could not complete' "$TOPTMP/mgm-red" || grep -qF 'semgrep could not complete' "$TOPTMP/mgm-green"; then
      skip_ "T-mutation-gitlink-mode-blanket" "semgrep itself failed (registry unreachable?) — mutation direction unprovable here"
    elif ! grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/mgm-red"; then
      skip_ "T-mutation-gitlink-mode-blanket" "the widened mutant printed no [OK] either (scanner did not run?) — the RED direction is unprovable here"
    elif grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/mgm-green"; then
      fail_ "T-mutation-gitlink-mode-blanket" "the GREEN hook ALSO printed an [OK] receipt over a silently-skipped non-blob entry — the mode test is not doing anything: $(grep -F '[OK] semgrep: SAST ran' "$TOPTMP/mgm-green" | head -1)"
    elif ! grep -qxF "    - weird.ts" "$TOPTMP/mgm-green"; then
      fail_ "T-mutation-gitlink-mode-blanket" "the GREEN hook suppressed the receipt but never NAMED the entry it could not read: $(tail -4 "$TOPTMP/mgm-green" | tr '\n' '|')"
    elif [ "$MGM_RED" != "COMMITTED" ] || [ "$MGM_GRN" != "COMMITTED" ]; then
      fail_ "T-mutation-gitlink-mode-blanket" "both directions must LAND (an unreadable entry WARNs, never blocks); got RED=$MGM_RED GREEN=$MGM_GRN"
    else
      pass "T-mutation-gitlink-mode-blanket: widening the skip's 160000 MODE test to a blanket match buys an UNEARNED [OK] over an unscanned staged entry (RED); the mode-gated skip forfeits the receipt and names it (GREEN) — the mode test is load-bearing (R-WPC2-1)"
    fi
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# R-274R-1 — the SCANNER's own target filter (the fifth silent-success instance,
# and the first to emit a POSITIVE FALSE ATTESTATION rather than lose a verdict)
# ═════════════════════════════════════════════════════════════════════════════
# _oversize_commit <hookfile> <log> -> COMMITTED|REFUSED|SETUPFAIL|NOGEN
#   Stage TWO blobs: an OVERSIZE one carrying the innerHTML sink, and a small CLEAN
#   sibling. The sibling is load-bearing in two ways — it keeps the target set at 2 so a
#   shortfall is measurable (1 accepted of 2 handed), and it is what made the pre-fix
#   receipt read `[OK] … ran on 2 staged file(s)` while semgrep had opened exactly one.
_oversize_commit() {
  local d; d="$(mktemp -d)"
  mk_repo "$d" "$1" >/dev/null 2>&1 || { rm -rf "$d"; echo SETUPFAIL; return; }
  write_oversize "$d/big.ts" "$XSS_TS"
  is_oversize "$d/big.ts" || { rm -rf "$d"; echo NOGEN; return; }
  printf '%s\n' "$SAFE_TS" > "$d/app.ts"
  ( cd "$d" && git add -- big.ts app.ts ) >/dev/null 2>&1
  # The staged BLOB must really carry the sink — a fixture that stages clean bytes
  # would "pass" every direction of every case below while proving nothing.
  #   VIA A FILE, NOT A PIPE, and that is not a style choice: `git cat-file blob | grep -q`
  #   makes grep exit at the first match while git is still writing a megabyte, git dies
  #   of SIGPIPE, and under this suite's `pipefail` the pipeline reports FAILURE on a
  #   fixture that is perfectly correct. The other cat-file probes in this file pipe
  #   safely only because their blobs are a few hundred bytes.
  ( cd "$d" && git cat-file blob ":0:big.ts" ) > "$TOPTMP/oversize-probe" 2>/dev/null
  if ! grep -q 'innerHTML' "$TOPTMP/oversize-probe"; then
    rm -rf "$d"; echo SETUPFAIL; return
  fi
  if ( cd "$d" && git commit -m "feat: add the bundled renderer" ) >"$2" 2>&1; then echo COMMITTED; else echo REFUSED; fi
  rm -rf "$d"
}

echo "=== T-oversize-blob-scanned ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-oversize-blob-scanned" "semgrep ABSENT — the scanner's own target filter is UNPROVEN here (skip, NOT a pass)"
else
  OS_V="$(_oversize_commit "$EMITTED" "$TOPTMP/oversize")"
  if [ "$OS_V" = "NOGEN" ]; then
    skip_ "T-oversize-blob-scanned" "this host could not build a >${OVERSIZE_MIN}-byte fixture — UNPROVEN here"
  elif [ "$OS_V" = "SETUPFAIL" ]; then
    fail_ "T-oversize-blob-scanned" "fixture setup failed — the staged oversize blob carries no sink, so the case proves nothing"
  elif not_enforced "$TOPTMP/oversize" && ! grep -qF 'coverage of the staged commit' "$TOPTMP/oversize"; then
    skip_ "T-oversize-blob-scanned" "scanner did not run (registry unreachable?) — UNPROVEN here"
  elif [ "$OS_V" = "REFUSED" ] && grep -qF '[BLOCKED] Semgrep' "$TOPTMP/oversize"; then
    pass "T-oversize-blob-scanned: a >1MB staged blob is SCANNED and its sink BLOCKS the commit (# BL-112-MAX-TARGET-BYTES)"
  elif grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/oversize"; then
    fail_ "T-oversize-blob-scanned" "an UNEARNED [OK] receipt over a staged blob semgrep never opened — the scanner's default --max-target-bytes dropped it silently (R-274R-1); receipt: $(grep -F '[OK] semgrep: SAST ran' "$TOPTMP/oversize" | head -1)"
  else
    fail_ "T-oversize-blob-scanned" "verdict=$OS_V without a [BLOCKED]: $(tail -4 "$TOPTMP/oversize" | tr '\n' '|')"
  fi
fi

# ── T-coverage-parse-fails-closed (the parser must not become the new silent path) ──
# Break the scan-status parse exactly as a future semgrep output redesign would: the
# grep that locates the `Scanning N files with M Code rules:` header no longer matches,
# so soif_sg_accepted stays EMPTY. A FULLY-COVERED, CLEAN commit must then take the loud
# NOTRUN — not [OK]. Without this the fix's own parser is the sixth member of the class:
# a guard that silently answers "covered" whenever it cannot read the evidence.
#   The fixture is deliberately the BORING case (one small clean file, complete
#   coverage), because that is the commit a fail-OPEN parser would wave through.
echo "=== T-coverage-parse-fails-closed ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-coverage-parse-fails-closed" "semgrep ABSENT — UNPROVEN here (skip, not pass)"
else
  MCP="$TOPTMP/mut-cov-parse"
  _clean_commit() {  # <hookfile> <log> -> COMMITTED|REFUSED|SETUPFAIL
    local d; d="$(mktemp -d)"
    mk_repo "$d" "$1" >/dev/null 2>&1 || { rm -rf "$d"; echo SETUPFAIL; return; }
    printf '%s\n' "$SAFE_TS" > "$d/app.ts"
    ( cd "$d" && git add -- app.ts ) >/dev/null 2>&1
    if ( cd "$d" && git commit -m "feat: add a clean renderer" ) >"$2" 2>&1; then echo COMMITTED; else echo REFUSED; fi
    rm -rf "$d"
  }
  if ! _mut_n "$EMITTED" "$MCP" 'Scanning [0-9][0-9]* files? with' 'SoifNoSuchBanner [0-9][0-9]* files? with' 1; then
    fail_ "T-coverage-parse-fails-closed" "MIS-TARGETED — the scan-status grep pattern is not present exactly once in the emitted hook (the parse moved; retarget this case in lockstep)"
  elif ! grep -qF '# BL-112-SCAN-COVERAGE' "$MCP"; then
    fail_ "T-coverage-parse-fails-closed" "mutation removed the marker — it must attack BEHAVIOUR, not the marker"
  elif ! bash -n "$MCP" 2>/dev/null; then
    fail_ "T-coverage-parse-fails-closed" "mutated hook has a syntax error — a broken mutant proves nothing"
  else
    CP_RED="$(_clean_commit "$MCP" "$TOPTMP/cp-red")"
    CP_GRN="$(_clean_commit "$EMITTED" "$TOPTMP/cp-green")"
    if [ "$CP_RED" = "SETUPFAIL" ] || [ "$CP_GRN" = "SETUPFAIL" ]; then
      fail_ "T-coverage-parse-fails-closed" "fixture setup failed"
    elif ! grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/cp-green"; then
      skip_ "T-coverage-parse-fails-closed" "the unmutated hook did not receipt a clean, fully-covered commit (scanner did not run?) — UNPROVEN here: $(tail -3 "$TOPTMP/cp-green" | tr '\n' '|')"
    elif grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/cp-red"; then
      fail_ "T-coverage-parse-fails-closed" "an unreadable scan-status line FELL THROUGH TO [OK] — the coverage parse fails OPEN, which makes the guard itself a silent-success path: $(grep -F '[OK] semgrep: SAST ran' "$TOPTMP/cp-red" | head -1)"
    elif not_enforced "$TOPTMP/cp-red" && grep -qF 'CANNOT BE VERIFIED' "$TOPTMP/cp-red" && [ "$CP_RED" = "COMMITTED" ]; then
      pass "T-coverage-parse-fails-closed: an unreadable scan-status line routes to the loud NOTRUN and never to [OK] (# BL-112-SCAN-COVERAGE fails CLOSED)"
    else
      fail_ "T-coverage-parse-fails-closed" "expected the broken parse to LAND with a loud UNVERIFIED NOTRUN; got RED=$CP_RED: $(tail -5 "$TOPTMP/cp-red" | tr '\n' '|')"
    fi
  fi
fi

# ── T-mutation-max-target-bytes (proof (a): the flag retires the TRIGGER) ─────
# Strip exactly the --max-target-bytes=0 continuation line. Semgrep's default 1,000,000
# filter comes back, the oversize blob is never opened, its sink is never seen and the
# commit LANDS (RED). Restore the line and the same commit is REFUSED with [BLOCKED]
# naming big.ts (GREEN).
#   THE RED ALSO ASSERTS THE ABSENCE OF [OK]. That is the division of labour between the
#   two halves of this fix: with the flag gone the sink escapes, but the coverage guard
#   must STILL refuse to certify the commit. A RED that printed [OK] would mean the class
#   guard is not doing its job either — and the case below proves it the other way round.
echo "=== T-mutation-max-target-bytes ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-mutation-max-target-bytes" "semgrep ABSENT — mutation UNPROVEN (skip, not pass)"
else
  MMB="$TOPTMP/mut-no-maxbytes"
  # sed, not _mut_n, for this one: the target is a whole CONTINUATION LINE and its
  # literal ends in a backslash, which awk's `-v` assignment processes as an escape —
  # _mut_n would silently mutate the wrong thing. The exactly-once count that makes
  # _mut_n a mis-target detector is kept, just spelled out here. Anchored ^…$ on the
  # full line so the flag's appearances in this arm's PROSE cannot be hit.
  MMB_N=$(grep -c '^        --max-target-bytes=0 \\$' "$EMITTED") || MMB_N=0
  MMB_N=$(printf '%s' "$MMB_N" | tr -d '[:space:]')
  case "$MMB_N" in ''|*[!0-9]*) MMB_N=0 ;; esac
  sed '/^        --max-target-bytes=0 \\$/d' "$EMITTED" > "$MMB"
  if [ "$MMB_N" -ne 1 ]; then
    fail_ "T-mutation-max-target-bytes" "MIS-TARGETED — the --max-target-bytes=0 continuation line is not present exactly once in the emitted hook (found $MMB_N)"
  elif ! bash -n "$MMB" 2>/dev/null; then
    fail_ "T-mutation-max-target-bytes" "mutated hook has a syntax error — a broken mutant proves nothing"
  else
    MMB_RED="$(_oversize_commit "$MMB" "$TOPTMP/mmb-red")"
    MMB_GRN="$(_oversize_commit "$EMITTED" "$TOPTMP/mmb-green")"
    if [ "$MMB_RED" = "NOGEN" ] || [ "$MMB_GRN" = "NOGEN" ]; then
      skip_ "T-mutation-max-target-bytes" "this host could not build a >${OVERSIZE_MIN}-byte fixture — mutation UNPROVEN here"
    elif [ "$MMB_RED" = "SETUPFAIL" ] || [ "$MMB_GRN" = "SETUPFAIL" ]; then
      fail_ "T-mutation-max-target-bytes" "mutation fixture setup failed"
    elif [ "$MMB_GRN" != "REFUSED" ] || ! grep -qF '[BLOCKED] Semgrep' "$TOPTMP/mmb-green"; then
      fail_ "T-mutation-max-target-bytes" "the GREEN (unmutated) side did not block the oversize sink — the flag is not doing what this case claims: verdict=$MMB_GRN: $(tail -4 "$TOPTMP/mmb-green" | tr '\n' '|')"
    elif [ "$MMB_RED" = "REFUSED" ]; then
      skip_ "T-mutation-max-target-bytes" "this host's semgrep scanned the >1MB target even WITHOUT --max-target-bytes=0 (no default size filter here) — the RED direction is unreproducible, so the flag's necessity is UNPROVEN on this host"
    elif grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/mmb-red"; then
      fail_ "T-mutation-max-target-bytes" "with the flag stripped the arm printed an [OK] receipt over an unscanned blob — # BL-112-SCAN-COVERAGE should have forfeited it: $(grep -F '[OK] semgrep: SAST ran' "$TOPTMP/mmb-red" | head -1)"
    else
      pass "T-mutation-max-target-bytes: stripping --max-target-bytes=0 lets the >1MB sink LAND (RED, and still no [OK]); restored, the same commit is REFUSED with [BLOCKED] (GREEN)"
    fi
  fi
fi

# ── T-mutation-scan-coverage (proof (b): the guard retires the CLASS) ────────
# Start from the flag-stripped hook above — i.e. an arm that provably hands semgrep a
# target it will decline — and neuter ONLY # BL-112-SCAN-COVERAGE's verdict
# (`soif_sg_covered=0` -> `=1`, so the arm always believes it was fully covered). The
# unscanned oversize blob then buys the `[OK] … ran on 2 staged file(s)` receipt and its
# sink LANDS (RED). Restore the guard alone — the flag stays stripped — and the same
# commit forfeits the receipt and prints the loud coverage NOTRUN naming both staged
# entries (GREEN).
#   THIS IS THE CASE THAT DISTINGUISHES THE TWO HALVES OF THE FIX. Shipping only the
#   flag would leave this suite green while the class stayed open: the sixth trigger
#   (a per-rule timeout, a parse skip, whatever semgrep adds next) would print [OK] all
#   over again. The mutant deliberately keeps the flag OFF so the guard is tested on a
#   real shortfall rather than a synthetic one.
#   THE RED ASSERTION IS THE RECEIPT, NOT THE LANDING — the commit lands in BOTH
#   directions here (a coverage gap WARNs, it never blocks), so "it committed" would be
#   satisfied by the honest arm too.
echo "=== T-mutation-scan-coverage ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-mutation-scan-coverage" "semgrep ABSENT — mutation UNPROVEN (skip, not pass)"
else
  MSC="$TOPTMP/mut-cov-neutered"
  if [ ! -f "$TOPTMP/mut-no-maxbytes" ]; then
    skip_ "T-mutation-scan-coverage" "the flag-stripped base hook was not built (see T-mutation-max-target-bytes) — UNPROVEN here"
  elif ! _mut_n "$TOPTMP/mut-no-maxbytes" "$MSC" 'soif_sg_covered=0' 'soif_sg_covered=1' 1; then
    fail_ "T-mutation-scan-coverage" "MIS-TARGETED — the coverage verdict assignment is not present exactly once in the emitted hook"
  elif ! grep -qF '# BL-112-SCAN-COVERAGE' "$MSC"; then
    fail_ "T-mutation-scan-coverage" "mutation removed the marker — it must attack BEHAVIOUR, not the marker"
  elif ! bash -n "$MSC" 2>/dev/null; then
    fail_ "T-mutation-scan-coverage" "mutated hook has a syntax error — a broken mutant proves nothing"
  else
    MSC_RED="$(_oversize_commit "$MSC" "$TOPTMP/msc-red")"
    MSC_GRN="$(_oversize_commit "$TOPTMP/mut-no-maxbytes" "$TOPTMP/msc-green")"
    if [ "$MSC_RED" = "NOGEN" ] || [ "$MSC_GRN" = "NOGEN" ]; then
      skip_ "T-mutation-scan-coverage" "this host could not build a >${OVERSIZE_MIN}-byte fixture — mutation UNPROVEN here"
    elif [ "$MSC_RED" = "SETUPFAIL" ] || [ "$MSC_GRN" = "SETUPFAIL" ]; then
      fail_ "T-mutation-scan-coverage" "mutation fixture setup failed"
    elif [ "$MSC_GRN" = "REFUSED" ]; then
      skip_ "T-mutation-scan-coverage" "this host's semgrep scanned the >1MB target even without --max-target-bytes=0 — no shortfall exists to detect, so the guard is UNPROVEN here"
    elif ! grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/msc-red"; then
      skip_ "T-mutation-scan-coverage" "the neutered mutant printed no [OK] either (scanner did not run?) — the RED direction is unprovable here: $(tail -3 "$TOPTMP/msc-red" | tr '\n' '|')"
    elif grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/msc-green"; then
      fail_ "T-mutation-scan-coverage" "the GREEN hook ALSO printed [OK] over a target semgrep declined — # BL-112-SCAN-COVERAGE is not doing anything: $(grep -F '[OK] semgrep: SAST ran' "$TOPTMP/msc-green" | head -1)"
    elif ! grep -qxF "    - big.ts" "$TOPTMP/msc-green" || ! grep -qxF "    - app.ts" "$TOPTMP/msc-green"; then
      fail_ "T-mutation-scan-coverage" "the GREEN hook forfeited the receipt but never NAMED the staged entries handed to the scanner (# BL-182-NAME-THE-ENTRY contract): $(tail -6 "$TOPTMP/msc-green" | tr '\n' '|')"
    else
      pass "T-mutation-scan-coverage: neutering the coverage verdict buys an UNEARNED [OK] over a target semgrep never opened (RED); the guard forfeits the receipt and NAMES the staged set (GREEN) — the class fix is load-bearing independently of the flag"
    fi
  fi
fi

echo ""
if [ "$SKIPPED" -gt 0 ]; then echo "!! $SKIPPED case(s) SKIPPED — skipped != passed."; fi
echo "Results: $PASSED passed, $FAILED failed ($SKIPPED skipped)"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

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
#   NOT IN THIS SUITE, AND THE ABSENCE IS DELIBERATE — THE PARSE/DECODE STAGE.
#                                 FIVE cases covering a `Parsed lines: ~N%` clause
#                                 (T-utf16-parse-drop-no-receipt, T-mutation-parse-coverage,
#                                 T-parse-coverage-fails-closed, T-parse-threshold-exact,
#                                 T-mutation-parse-threshold) were
#                                 written, measured and WITHDRAWN before merge. FIVE, NOT
#                                 SIX — the set difference against
#                                 origin/fix/bl112-sast-scan-coverage (e87dbd3) leaves SIX
#                                 parse-named cases, but T-parse-coverage-no-cry-wolf was
#                                 RENAMED to T-coverage-no-cry-wolf and KEPT (below), and
#                                 T-empty-target-receipt was KEPT and rescoped. Count the
#                                 withdrawals, not the renames. The clause
#                                 works on semgrep 1.157.0 and is BLIND on >= 1.171.0, where
#                                 the banner reads `Parsed lines: ~100.0%` for a file semgrep
#                                 never decoded. Do not re-add the cases without re-measuring
#                                 the instrument — a green suite on a pinned old semgrep is
#                                 exactly how this gap would ship. Filed as BL-192.
#   T-empty-target-receipt        live — the OTHER cry-wolf shape: a zero-byte staged file
#                                 (a .gitkeep, an empty __init__.py) must still EARN the
#                                 receipt. Written for the withdrawn parse clause and KEPT:
#                                 what survives is an unmeasured cry-wolf risk on the
#                                 SELECTION clause — a `Scanning 0 files` header would NOTRUN
#                                 every placeholder commit forever.
#   T-coverage-no-cry-wolf        live — the counter-objection that ruled `Targets scanned`
#                                 OUT must not apply to the clauses that DID ship: an
#                                 ordinary multi-language commit (ts + md + json + yml + sh)
#                                 must still EARN the [OK] receipt. A guard that NOTRUNs
#                                 normal commits is a gate people route around.
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
#   T-mutation-max-target-bytes-value  live — R-274Rv2-4: pin the flag's VALUE, not just the
#                                 line. Set it to semgrep's own 1000000 default -> the >1MB
#                                 sink LANDS (RED, receipt still forfeited) -> back to 0 ->
#                                 REFUSED + [BLOCKED] (GREEN). Deleting the line alone leaves
#                                 the value unpinned by BEHAVIOUR.
#   T-oversize-dense-no-receipt   live — R-274Rv2-1: a >1MB DENSE .ts (code padding, not
#                                 comments) is ACCEPTED and then the one rule that catches its
#                                 line-2 sink hits semgrep's default 5s per-rule timeout. Every
#                                 selection fact reads complete and the arm certified it. Must
#                                 be [BLOCKED] or a loud rule-coverage NOTRUN, never [OK].
#                                 DENSITY is the variable — comment padding cannot provoke it.
#   T-rule-timeout-names-the-rule live — the forfeited receipt names the TARGET and the exact
#                                 RULE that ran out of time, with the temp-tree prefix mapped
#                                 off (# BL-182-NAME-THE-ENTRY, where this arm CAN attribute).
#   T-mutation-rule-timeout       live — drop ONLY the rule-timeout clause from the coverage
#                                 conjunction -> the dense sink buys an [OK] again (RED) ->
#                                 restore -> forfeited + staged set named (GREEN). Selection is
#                                 left intact, so it proves the clause carries its own weight.
#   T-scan-status-singular-rule   stub — R-274Rv2-8: semgrep really prints the SINGULAR
#                                 `Scanning 1 file with 1 Code rule:` for a one-rule resolved
#                                 set. The header parse hard-required the plural, which was a
#                                 PERMANENT NOTRUN cliff (every commit, forever). Both
#                                 spellings accepted; narrowing the grep back goes RED.
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
# write_oversize_dense <dest> <first-lines>: THE SAME SHAPE WITH CODE PADDING INSTEAD OF
# COMMENT PADDING, AND THE DIFFERENCE IS THE WHOLE POINT OF THE CASES BELOW (R-274Rv2-3).
# write_oversize above pads with 7,000 identical `// paddingpadding…` COMMENT lines, which
# is the one >1MB shape that structurally CANNOT provoke a per-rule timeout: comments cost
# a rule almost nothing to walk. Every oversize case in this suite rode that fixture, so
# the suite proved --max-target-bytes=0 on precisely the large-file shape that is immune to
# the residue which made the flag insufficient. Measured through the shipped emitter on
# semgrep 1.157.0, same sink on line 2, same pristine hook, opposite verdicts:
#   comment-padded 1,253,093 bytes -> REFUSED   [BLOCKED]
#   code-padded    1,216,567 bytes -> COMMITTED [OK] … ran on 1 staged file(s)
# The padding here is ordinary generated-bundle-looking TypeScript — object literals with
# an arrow function each — so the rules have real AST to walk and the rule that catches the
# line-2 innerHTML sink runs out of semgrep's default 5-second per-rule budget.
#   NOT A LOAD-BEARING CONSTANT: the exact line count is a means to a byte size, and every
#   case re-probes with is_oversize and LOUD-SKIPs rather than passing vacuously. What IS
#   load-bearing is that the padding is CODE. Replace it with comments and every case below
#   goes green while proving nothing — that is the bug this fixture exists to stop.
write_oversize_dense() {
  { printf '%s\n' "$2"
    awk 'BEGIN{ for(i=0;i<12000;i++) printf "const v%06d = { a: %d, b: [%d, %d], f: (x: number) => x * %d + %d, s: \"payload%06d\" };\n", i, i, i, i+1, i+2, i+3, i }'
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

# BL-193-EVIDENCE — print the SAST section, not a blind tail.
# The three cases that use this (T-coverage-no-cry-wolf, T-empty-target-receipt,
# T-mutation-typechange-filter) fail ONLY on the GitHub runner and pass on every
# local platform tried, including on CI own semgrep 1.172.0. So the CI transcript
# IS the diagnosis — and each of them ended its message with a `tail -8`/`tail -3`
# of the hook output, which on these fixtures lands on the unrelated
# `[WARN] no test command configured` block plus git commit summary. The SAST
# section was captured to the log and then discarded at the moment of capture:
# the BL-184 evidence-destruction class, one level below the aggregator.
# The pattern matches every arm of the emitted hook SAST reporter vocabulary plus
# semgrep own banner, so an arm firing for an unanticipated reason is still shown
# instead of being filtered out by a guess about which arm it will be.
# FALSIFIER: point it at a log with no SAST section — it prints
# `(no SAST section in <path>)` rather than nothing. Silence would be
# indistinguishable from a helper that failed to run.
sast_evidence() {  # <logfile> -> one line, pipe-separated
  awk '
    /semgrep|SAST|\[BLOCKED\]|\[OK\]|Staged entries|Scanning|Targets scanned|coverage|scanner|NOTRUN/ {
      n++; printf "%s|", $0
    }
    END { if (!n) printf "(no SAST section in %s)", FILENAME }
  ' "$1"
}

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

# ── T-status-on-stdout-earns-receipt (BL-193) ────────────────────────────────
# WHICH STREAM semgrep puts its scan-status banner on is a frontend implementation
# detail, not a contract. Measured 2026-07-29: STDERR on this macOS host, STDOUT on
# the GitHub Linux runner. The coverage guard hard-coded stderr, so on the runner the
# header count read 0, coverage could never be verified, and the emitted hook NOTRUNed
# EVERY clean commit — a permanent cry-wolf on any host that routes it that way. This
# case pins the fix (# BL-193-STATUS-STREAM) with a semgrep shim that behaves exactly
# like the runner: banner on STDOUT, findings none, exit 0.
# Hermetic and deterministic — no real semgrep, no registry, no network — so unlike the
# three cases this defect actually broke, it cannot go UNPROVEN on a quiet host.
echo "=== T-status-on-stdout-earns-receipt ==="
SG_STDOUT_DIR="$TOPTMP/sgshim-stdout"
mkdir -p "$SG_STDOUT_DIR"
cat > "$SG_STDOUT_DIR/semgrep" <<'SHIM'
#!/usr/bin/env bash
# Count the target paths the hook handed us, then print the scan-status banner on
# STDOUT (the runner's behaviour) and nothing on stderr. Exit 0, no findings.
n=0
for a in "$@"; do case "$a" in -*) ;; *) n=$((n + 1)) ;; esac; done
echo "  Scanning ${n} files with 174 Code rules:"
exit 0
SHIM
chmod +x "$SG_STDOUT_DIR/semgrep"
R_SO="$TOPTMP/status-stdout"
if ! mk_repo "$R_SO" "$EMITTED"; then
  fail_ "T-status-on-stdout-earns-receipt" "fixture setup failed"
else
  printf 'export function r(el, u) {\n  el.textContent = u;\n}\n' > "$R_SO/app.ts"
  ( cd "$R_SO" && git add app.ts ) >/dev/null 2>&1
  SO_OUT="$TOPTMP/status-stdout.log"
  ( cd "$R_SO" && PATH="$SG_STDOUT_DIR:$PATH" git commit -m "feat: add the renderer" ) > "$SO_OUT" 2>&1
  SO_RC=$?
  if [ "$SO_RC" -ne 0 ]; then
    fail_ "T-status-on-stdout-earns-receipt" "the commit was REFUSED with a clean shim scan: $(sast_evidence "$SO_OUT")"
  elif ! grep -qF '[OK] semgrep: SAST ran' "$SO_OUT"; then
    fail_ "T-status-on-stdout-earns-receipt" "a banner on STDOUT forfeited the receipt — the coverage guard is reading only one stream again (BL-193): $(sast_evidence "$SO_OUT")"
  else
    pass "T-status-on-stdout-earns-receipt: a scan-status banner on STDOUT still earns the [OK] receipt (# BL-193-STATUS-STREAM)"
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
      fail_ "T-mutation-typechange-filter" "expected RED=COMMITTED+[OK]-receipt / GREEN=REFUSED+[BLOCKED]; got RED=$MTF_RED (ok=$(grep -cF '[OK] semgrep: SAST ran' "$TOPTMP/mtf-red")) GREEN=$MTF_GRN (blocked=$(grep -cF '[BLOCKED]' "$TOPTMP/mtf-green")); red: $(sast_evidence "$TOPTMP/mtf-red"); green: $(sast_evidence "$TOPTMP/mtf-green")"
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
  if ! _mut_n "$EMITTED" "$MPR" 'elif [ "${#soif_idx_unread[@]}" -gt 0 ] || [ "${#soif_idx_untx[@]}" -gt 0 ]; then' 'elif false; then' 1; then
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

# ── T-coverage-no-cry-wolf (every coverage clause must survive an ordinary commit) ──
# A coverage clause is only admissible if it does not NOTRUN normal work — a gate that
# always cries wolf is a gate people route around, which is the culture BL-112 exists to
# end. So pin the negative: an ordinary mixed-language commit must still EARN its receipt.
#   THIS HEADER USED TO JUSTIFY ITSELF WITH A MEASUREMENT THAT IS FALSE. It said
#   `Targets scanned` was ruled out because it "reads 1-of-2 for the wholly ordinary commit
#   app.ts + README.md". Re-measured on semgrep 1.157.0 with this arm's exact flag set
#   (R-274Rv2-5): `app.ts + README.md` reports `Targets scanned: 2`, and `README.md` alone
#   reports 1 — the resolved ruleset contains `<multilang>` rules that match every target
#   regardless of language. The real reason that counter was ruled out is that it is
#   REGISTRY-DEPENDENT (change a --config and it becomes a language-match count without
#   anything in the hook changing), which is recorded on `# BL-112-SCAN-COVERAGE`. The
#   case below is unchanged and is worth strictly more than the story it was told with:
#   it now guards BOTH shipped clauses — selection and rule-timeout — at once. (A third,
#   parse/decode, was withdrawn before merge; see the CASES header and BL-192.)
echo "=== T-coverage-no-cry-wolf ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-coverage-no-cry-wolf" "semgrep ABSENT — UNPROVEN here (skip, not pass)"
else
  _mixed_commit() {  # <hookfile> <log> -> COMMITTED|REFUSED|SETUPFAIL
    local d; d="$(mktemp -d)"
    mk_repo "$d" "$1" >/dev/null 2>&1 || { rm -rf "$d"; echo SETUPFAIL; return; }
    printf '%s\n' "$SAFE_TS" > "$d/app.ts"
    printf '# notes\n\nsome prose\n' > "$d/NOTES.md"
    printf '{"a":1,"b":[1,2,3]}\n' > "$d/cfg.json"
    printf 'a: 1\nb:\n  - x\n' > "$d/ci.yml"
    printf '#!/usr/bin/env bash\nset -euo pipefail\necho hi\n' > "$d/run.sh"
    ( cd "$d" && git add -- app.ts NOTES.md cfg.json ci.yml run.sh ) >/dev/null 2>&1
    if ( cd "$d" && git commit -m "feat: add the renderer and its config" ) >"$2" 2>&1; then echo COMMITTED; else echo REFUSED; fi
    rm -rf "$d"
  }
  CW_V="$(_mixed_commit "$EMITTED" "$TOPTMP/crywolf")"
  if [ "$CW_V" = "SETUPFAIL" ]; then
    fail_ "T-coverage-no-cry-wolf" "fixture setup failed"
  elif ! any_sast_line "$TOPTMP/crywolf"; then
    skip_ "T-coverage-no-cry-wolf" "scanner did not run (registry unreachable?) — UNPROVEN here"
  elif grep -qF '[OK] semgrep: SAST ran on 5 staged file(s)' "$TOPTMP/crywolf"; then
    pass "T-coverage-no-cry-wolf: an ordinary ts+md+json+yml+sh commit still EARNS the [OK] receipt — # BL-112-SCAN-COVERAGE does not NOTRUN normal commits"
  else
    fail_ "T-coverage-no-cry-wolf" "an ordinary 5-file commit lost its receipt — # BL-112-SCAN-COVERAGE is crying wolf, which is exactly why 'Targets scanned' was ruled out: verdict=$CW_V: $(sast_evidence "$TOPTMP/crywolf")"
  fi
fi

# ── T-empty-target-receipt (the OTHER cry-wolf shape: a zero-byte staged file) ────
# `touch src/placeholder.ts && git add && git commit` — a .gitkeep, an empty __init__.py,
# a stub module. Wholly ordinary, and it must still EARN the receipt.
#   THIS CASE WAS WRITTEN FOR THE WITHDRAWN PARSE CLAUSE AND IS KEPT ANYWAY, DELIBERATELY.
#   Its original target was a zero-DENOMINATOR percentage (semgrep prints the words "an
#   unknown percentage" when every target has zero lines), which the first cut of the parse
#   clause read as lost coverage and NOTRUNed. That clause is gone (BL-192). What survives
#   is a cry-wolf risk on a clause that DID ship: nothing here has measured what semgrep's
#   Scan Status header says for an all-empty target set, and if it ever reads `Scanning 0
#   files` the SELECTION clause forfeits the receipt on every placeholder commit in every
#   generated project — forever, not per-commit. That is the permanent-NOTRUN cliff shape
#   T-scan-status-singular-rule exists for, on the most ordinary fixture imaginable, and it
#   costs one case to pin. Do not delete this with the parse work it was born from.
echo "=== T-empty-target-receipt ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-empty-target-receipt" "semgrep ABSENT — UNPROVEN here (skip, not pass)"
else
  _empty_commit() {  # <hookfile> <log> -> COMMITTED|REFUSED|SETUPFAIL
    local d; d="$(mktemp -d)"
    mk_repo "$d" "$1" >/dev/null 2>&1 || { rm -rf "$d"; echo SETUPFAIL; return; }
    : > "$d/placeholder.ts"
    ( cd "$d" && git add -- placeholder.ts ) >/dev/null 2>&1
    # A staged ZERO-BYTE blob is the whole point; if git or the host turned it into
    # something else the case is measuring the wrong thing.
    [ "$( ( cd "$d" && git cat-file -s ":0:placeholder.ts" ) 2>/dev/null )" = "0" ] || { rm -rf "$d"; echo SETUPFAIL; return; }
    if ( cd "$d" && git commit -m "feat: add the placeholder module" ) >"$2" 2>&1; then echo COMMITTED; else echo REFUSED; fi
    rm -rf "$d"
  }
  ET_V="$(_empty_commit "$EMITTED" "$TOPTMP/emptytgt")"
  if [ "$ET_V" = "SETUPFAIL" ]; then
    fail_ "T-empty-target-receipt" "fixture setup failed — the staged blob is not zero bytes, so the case proves nothing"
  elif ! any_sast_line "$TOPTMP/emptytgt"; then
    skip_ "T-empty-target-receipt" "scanner did not run (registry unreachable?) — UNPROVEN here"
  elif grep -qF '[OK] semgrep: SAST ran on 1 staged file(s)' "$TOPTMP/emptytgt"; then
    pass "T-empty-target-receipt: a zero-byte staged file still EARNS the receipt — semgrep's scan-status header counts it as an accepted target, so # BL-112-SCAN-COVERAGE does not cry wolf on a placeholder"
  else
    fail_ "T-empty-target-receipt" "an ordinary empty placeholder file lost its receipt — # BL-112-SCAN-COVERAGE is treating 'nothing to scan' as 'a target was declined', which would NOTRUN every .gitkeep commit forever: verdict=$ET_V: $(sast_evidence "$TOPTMP/emptytgt")"
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# R-274Rv2-1 — the SEVENTH silent-success instance: a target semgrep accepts, parses
# IN FULL, and then ABANDONS a rule on its per-rule timeout. Selection said complete,
# parse said 100.0%, rc was 0, and the arm certified a commit whose line-2 innerHTML
# sink no rule ever matched. # BL-187-RULE-COVERAGE reads the one line in the default
# banner that reports it: `Warning: N timeout error(s) in <target> …`.
# ═════════════════════════════════════════════════════════════════════════════
# _dense_oversize_commit <hookfile> <log> -> COMMITTED|REFUSED|SETUPFAIL|NOGEN
#   Deliberately ONE staged file, not the two _oversize_commit uses. This case is about
#   the stage AFTER selection, so a sibling would only add noise: semgrep accepts 1 of 1
#   and parses 100% of it, and the ONLY dissenting signal in the whole banner is the
#   timeout warning. Keeping the target set at one makes that unambiguous in the log.
_dense_oversize_commit() {
  local d; d="$(mktemp -d)"
  mk_repo "$d" "$1" >/dev/null 2>&1 || { rm -rf "$d"; echo SETUPFAIL; return; }
  write_oversize_dense "$d/heavy.ts" "$XSS_TS"
  is_oversize "$d/heavy.ts" || { rm -rf "$d"; echo NOGEN; return; }
  ( cd "$d" && git add -- heavy.ts ) >/dev/null 2>&1
  # The staged BLOB must carry the sink. Via a FILE, not a pipe — see the note in
  # _oversize_commit: `git cat-file blob | grep -q` on a megabyte dies of SIGPIPE under
  # this suite's `pipefail` and reports a failure on a perfectly correct fixture.
  ( cd "$d" && git cat-file blob ":0:heavy.ts" ) > "$TOPTMP/dense-probe" 2>/dev/null
  if ! grep -q 'innerHTML' "$TOPTMP/dense-probe"; then rm -rf "$d"; echo SETUPFAIL; return; fi
  if ( cd "$d" && git commit -m "feat: add the bundled renderer" ) >"$2" 2>&1; then echo COMMITTED; else echo REFUSED; fi
  rm -rf "$d"
}

# ── T-oversize-dense-no-receipt (the reproduced defect, RED before # BL-187-RULE-COVERAGE) ──
# A >1MB DENSE source file carrying the sink must be [BLOCKED] or LOUDLY NOTRUN — never
# [OK]. Watched RED against the pre-fix lib: verdict=COMMITTED with
# `[OK] semgrep: SAST ran on 1 staged file(s)` and the sink in HEAD, 5 runs out of 5.
#   THE ASSERTION IS THE RECEIPT, NOT THE LANDING. A rule-coverage gap WARNs and never
#   blocks (same contract as every other can't-scan path in this arm), so the commit lands
#   in both directions and "it committed" would be satisfied by the honest arm too.
#   BOTH GOOD OUTCOMES ARE ACCEPTED ON PURPOSE. A faster host — or a semgrep whose rule
#   finishes inside the budget — BLOCKS the sink outright, which is strictly better than
#   the contract requires. What is forbidden is the third outcome: a full receipt.
echo "=== T-oversize-dense-no-receipt ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-oversize-dense-no-receipt" "semgrep ABSENT — the rule-coverage guard is UNPROVEN here (skip, NOT a pass)"
else
  DZ_V="$(_dense_oversize_commit "$EMITTED" "$TOPTMP/dense")"
  if [ "$DZ_V" = "NOGEN" ]; then
    skip_ "T-oversize-dense-no-receipt" "this host could not build a >${OVERSIZE_MIN}-byte dense fixture — UNPROVEN here"
  elif [ "$DZ_V" = "SETUPFAIL" ]; then
    fail_ "T-oversize-dense-no-receipt" "fixture setup failed — the staged dense blob carries no sink, so the case proves nothing"
  elif ! any_sast_line "$TOPTMP/dense"; then
    skip_ "T-oversize-dense-no-receipt" "scanner did not run (registry unreachable?) — UNPROVEN here"
  elif grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/dense"; then
    fail_ "T-oversize-dense-no-receipt" "an UNEARNED [OK] receipt over a >1MB DENSE source file whose sink no rule ever matched — semgrep took it and then timed out on the one rule that catches it (R-274Rv2-1); receipt: $(grep -F '[OK] semgrep: SAST ran' "$TOPTMP/dense" | head -1)"
  elif [ "$DZ_V" = "REFUSED" ] && grep -qF '[BLOCKED] Semgrep' "$TOPTMP/dense"; then
    pass "T-oversize-dense-no-receipt: this host's semgrep finished the rule inside its budget and BLOCKED the dense >1MB sink outright — no false attestation possible"
  elif not_enforced "$TOPTMP/dense" && grep -qF 'Rule coverage:' "$TOPTMP/dense"; then
    pass "T-oversize-dense-no-receipt: a >1MB DENSE staged file whose rule TIMED OUT forfeits the [OK] receipt and reports rule coverage (# BL-187-RULE-COVERAGE)"
  else
    fail_ "T-oversize-dense-no-receipt" "verdict=$DZ_V with neither an [OK], a [BLOCKED], nor a rule-coverage NOTRUN: $(tail -8 "$TOPTMP/dense" | tr '\n' '|')"
  fi
fi

# ── T-rule-timeout-names-the-rule (# BL-182-NAME-THE-ENTRY, where it CAN attribute) ──
# The other two coverage guards cannot say WHICH target semgrep declined, and the report
# says so plainly. The timeout warning CAN: it names the target and the exact rule ids, so
# the report surfaces them — with the temp-tree prefix mapped off, because an operator
# shown a /var/folders/… path they cannot resolve has been told nothing.
echo "=== T-rule-timeout-names-the-rule ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-rule-timeout-names-the-rule" "semgrep ABSENT — UNPROVEN here (skip, not pass)"
elif [ ! -s "$TOPTMP/dense" ]; then
  skip_ "T-rule-timeout-names-the-rule" "the dense-oversize transcript was not produced (see T-oversize-dense-no-receipt) — UNPROVEN here"
# THIS GUARD IS A SKIP CONDITION, SO ITS STRINGS ARE LOAD-BEARING IN THE DANGEROUS
# DIRECTION: if they stop matching the hook's wording the case does not FAIL, it silently
# stops testing. It was moved in lockstep with the R-772-4 rewording of the rule-coverage
# sentence ("warning(s)" -> "warning line(s)", because the counter counts LINES and semgrep
# prints two of them per timeout once --timeout-threshold trips). On this host the case is
# an active PASS, not a skip — if it ever reports SKIP after a hook-wording change, fix the
# strings, do not accept the skip.
elif ! grep -qF 'Rule coverage: semgrep reported' "$TOPTMP/dense" || ! grep -qF 'rule-timeout warning line(s)' "$TOPTMP/dense"; then
  skip_ "T-rule-timeout-names-the-rule" "no rule timed out on this host, so there is nothing to attribute — UNPROVEN here"
elif ! grep -qF 'heavy.ts' "$TOPTMP/dense"; then
  fail_ "T-rule-timeout-names-the-rule" "the rule-coverage report never named the target: $(tail -8 "$TOPTMP/dense" | tr '\n' '|')"
elif grep -q "$TOPTMP" "$TOPTMP/dense" || grep -qE '/(var|tmp)/[^ ]*/heavy\.ts' "$TOPTMP/dense"; then
  fail_ "T-rule-timeout-names-the-rule" "the raw temp-tree prefix leaked into the operator-facing output — the path-mapping sed did not run over the timeout excerpt (F3): $(grep -F 'heavy.ts' "$TOPTMP/dense" | head -2 | tr '\n' '|')"
elif ! grep -qF 'insecure-document-method' "$TOPTMP/dense"; then
  fail_ "T-rule-timeout-names-the-rule" "the excerpt was cut before the rule ids — semgrep WRAPS that warning across two lines and the report must follow the wrap: $(grep -F 'timeout error' "$TOPTMP/dense" | tr '\n' '|')"
else
  pass "T-rule-timeout-names-the-rule: the forfeited receipt names the TARGET and the exact RULE that ran out of time, with the temp-tree prefix mapped off (# BL-182-NAME-THE-ENTRY)"
fi

# ── T-mutation-rule-timeout (proof: the SECOND shipped clause carries its own weight) ─
# Drop ONLY the rule-timeout clause from the coverage conjunction and leave selection
# untouched. That is exactly the shipped code as it stood before R-274Rv2-1 — semgrep
# accepted 1 of 1, so the surviving clause is satisfied and the arm certifies a commit
# whose sink no rule matched (RED). Restore the clause and the same commit forfeits its
# receipt (GREEN).
#   THE RED ASSERTION IS THE RECEIPT, NOT THE LANDING — the commit lands in both directions.
echo "=== T-mutation-rule-timeout ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-mutation-rule-timeout" "semgrep ABSENT — mutation UNPROVEN (skip, not pass)"
else
  MRT="$TOPTMP/mut-timeout-clause"
  if ! _mut_n "$EMITTED" "$MRT" ' && [ "$soif_sg_timeouts" -eq 0 ]' '' 1; then
    fail_ "T-mutation-rule-timeout" "MIS-TARGETED — the rule-timeout clause of the coverage conjunction is not present exactly once in the emitted hook"
  elif ! grep -qF '# BL-187-RULE-COVERAGE' "$MRT"; then
    fail_ "T-mutation-rule-timeout" "mutation removed the marker — it must attack BEHAVIOUR, not the marker"
  elif ! bash -n "$MRT" 2>/dev/null; then
    fail_ "T-mutation-rule-timeout" "mutated hook has a syntax error — a broken mutant proves nothing"
  else
    MRT_RED="$(_dense_oversize_commit "$MRT" "$TOPTMP/mrt-red")"
    MRT_GRN="$(_dense_oversize_commit "$EMITTED" "$TOPTMP/mrt-green")"
    if [ "$MRT_RED" = "NOGEN" ] || [ "$MRT_GRN" = "NOGEN" ]; then
      skip_ "T-mutation-rule-timeout" "this host could not build a >${OVERSIZE_MIN}-byte dense fixture — mutation UNPROVEN here"
    elif [ "$MRT_RED" = "SETUPFAIL" ] || [ "$MRT_GRN" = "SETUPFAIL" ]; then
      fail_ "T-mutation-rule-timeout" "mutation fixture setup failed"
    elif [ "$MRT_RED" = "REFUSED" ] || [ "$MRT_GRN" = "REFUSED" ]; then
      skip_ "T-mutation-rule-timeout" "this host's semgrep finished the rule inside its budget and blocked the sink — there is no timeout shortfall to detect, so the clause is UNPROVEN here"
    elif ! grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/mrt-red"; then
      skip_ "T-mutation-rule-timeout" "the mutant printed no [OK] either (scanner did not run?) — the RED direction is unprovable here: $(tail -3 "$TOPTMP/mrt-red" | tr '\n' '|')"
    elif grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/mrt-green"; then
      fail_ "T-mutation-rule-timeout" "the GREEN hook ALSO printed [OK] over a target whose rule timed out — # BL-187-RULE-COVERAGE is not doing anything: $(grep -F '[OK] semgrep: SAST ran' "$TOPTMP/mrt-green" | head -1)"
    elif ! grep -qxF "    - heavy.ts" "$TOPTMP/mrt-green"; then
      fail_ "T-mutation-rule-timeout" "the GREEN hook forfeited the receipt but never NAMED the staged entries handed to the scanner (# BL-182-NAME-THE-ENTRY contract): $(tail -8 "$TOPTMP/mrt-green" | tr '\n' '|')"
    else
      pass "T-mutation-rule-timeout: dropping the rule-timeout clause alone re-buys the UNEARNED [OK] over a target whose rule was abandoned (RED); restored, the receipt is forfeited and the staged set NAMED (GREEN) — the rule-execution clause is load-bearing independently of the selection clause"
    fi
  fi
fi

# ── T-mutation-max-target-bytes-value (R-274Rv2-4: pin the VALUE, not just the line) ──
# T-mutation-max-target-bytes DELETES the whole continuation line. That leaves the VALUE
# unpinned by behaviour: change `=0` to any large finite number and the only thing that
# fires is the exactly-once grep in that case, which reports MIS-TARGETED — a text detector
# reporting a text change, not a behavioural regression. CLAUDE.md's BL-181 lesson is
# exactly this ("pin each atom's WIDTH and its SPELLING, not just its presence").
#   A GENERAL value pin is impossible — you cannot stage a file larger than an arbitrary
#   constant — so this pins the ONE value that matters: `0` means "no limit" and anything
#   else is a cap. Setting it to semgrep's documented default (1000000) must reinstate the
#   exact R-274R-1 defect on the >1MB fixture (RED); `0` must scan it (GREEN).
echo "=== T-mutation-max-target-bytes-value ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-mutation-max-target-bytes-value" "semgrep ABSENT — mutation UNPROVEN (skip, not pass)"
else
  MTV="$TOPTMP/mut-maxbytes-value"
  # sed with the SAME anchored full-line literal T-mutation-max-target-bytes uses, and its
  # exactly-once count spelled out for the same reason: the literal ends in a backslash,
  # which awk's -v would process as an escape.
  MTV_N=$(grep -c '^        --max-target-bytes=0 \\$' "$EMITTED") || MTV_N=0
  MTV_N=$(printf '%s' "$MTV_N" | tr -d '[:space:]')
  case "$MTV_N" in ''|*[!0-9]*) MTV_N=0 ;; esac
  sed 's/^        --max-target-bytes=0 \\$/        --max-target-bytes=1000000 \\/' "$EMITTED" > "$MTV"
  if [ "$MTV_N" -ne 1 ]; then
    fail_ "T-mutation-max-target-bytes-value" "MIS-TARGETED — the --max-target-bytes=0 continuation line is not present exactly once in the emitted hook (found $MTV_N)"
  elif [ "$(grep -c '^        --max-target-bytes=1000000 \\$' "$MTV")" != "1" ]; then
    fail_ "T-mutation-max-target-bytes-value" "the value mutation did not apply — the case would prove nothing"
  elif ! bash -n "$MTV" 2>/dev/null; then
    fail_ "T-mutation-max-target-bytes-value" "mutated hook has a syntax error — a broken mutant proves nothing"
  else
    MTV_RED="$(_oversize_commit "$MTV" "$TOPTMP/mtv-red")"
    MTV_GRN="$(_oversize_commit "$EMITTED" "$TOPTMP/mtv-green")"
    if [ "$MTV_RED" = "NOGEN" ] || [ "$MTV_GRN" = "NOGEN" ]; then
      skip_ "T-mutation-max-target-bytes-value" "this host could not build a >${OVERSIZE_MIN}-byte fixture — mutation UNPROVEN here"
    elif [ "$MTV_RED" = "SETUPFAIL" ] || [ "$MTV_GRN" = "SETUPFAIL" ]; then
      fail_ "T-mutation-max-target-bytes-value" "mutation fixture setup failed"
    elif [ "$MTV_GRN" != "REFUSED" ] || ! grep -qF '[BLOCKED] Semgrep' "$TOPTMP/mtv-green"; then
      fail_ "T-mutation-max-target-bytes-value" "the GREEN (value=0) side did not block the oversize sink — the case is not measuring the value: verdict=$MTV_GRN: $(tail -4 "$TOPTMP/mtv-green" | tr '\n' '|')"
    elif [ "$MTV_RED" = "REFUSED" ]; then
      skip_ "T-mutation-max-target-bytes-value" "this host's semgrep scanned the >1MB target even at --max-target-bytes=1000000 — the RED direction is unreproducible, so the VALUE's necessity is UNPROVEN on this host"
    elif grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/mtv-red"; then
      fail_ "T-mutation-max-target-bytes-value" "at value=1000000 the arm printed an [OK] receipt over an unscanned blob — # BL-112-SCAN-COVERAGE should have forfeited it: $(grep -F '[OK] semgrep: SAST ran' "$TOPTMP/mtv-red" | head -1)"
    else
      pass "T-mutation-max-target-bytes-value: changing the flag's VALUE from 0 to semgrep's own 1000000 default reinstates R-274R-1 — the >1MB sink LANDS (RED, receipt still forfeited); at 0 the same commit is REFUSED with [BLOCKED] (GREEN). The value is behaviour, not spelling."
    fi
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# THE STUB-SEMGREP INSTRUMENT — for the property no real fixture can pin
# ═════════════════════════════════════════════════════════════════════════════
# Everything above drives the REAL scanner, deliberately, and that stays the rule. But one
# shipped property is arithmetic on semgrep's TEXT and cannot be provoked reliably by any
# file: the SINGULAR `Code rule:` header spelling, which needs a resolved ruleset of
# exactly one rule, i.e. a different --config set than the one this arm ships. A stub
# semgrep is the honest instrument for it: it tests THIS ARM'S PARSE of a banner, which is
# the property under test, and it says so in its name.
#   TWO FURTHER STUB CASES LIVED HERE AND WENT WITH THE WITHDRAWN PARSE CLAUSE
#   (T-parse-threshold-exact and T-mutation-parse-threshold, pinning the exact `>= 100`
#   threshold). Whoever restores a parse/decode clause restores them too — the threshold
#   was UNPINNED once already and a reviewer's `-ge 100` -> `-ge 99` mutant survived the
#   whole PR-blocking set. See BL-192.
#   IT IS NOT A SUBSTITUTE FOR THE REAL-PATH CASES and must never become one. It is still
#   driven through the SHIPPED emitter, a real .git/hooks/pre-commit and a real
#   `git commit` — only the scanner is fabricated.
#   EVERY STUB CASE CARRIES ITS OWN CONTROL. A stub that broke the arm outright would make
#   a bare "the receipt was forfeited" assertion pass vacuously, so each case also runs a
#   banner that MUST earn the receipt.
# mk_stub_semgrep <dir> <header-tail> <parsed-value>: an executable `semgrep` in <dir>
# printing nothing on stdout, a two-line banner on stderr, exit 0 (clean scan, no findings).
#   THE `Parsed lines:` LINE IS KEPT THOUGH THE SHIPPED HOOK NO LONGER READS IT. A stub
#   whose banner is narrower than the real one would stop being a faithful instrument the
#   moment the arm reads anything else from it, and the line costs nothing. It is also the
#   fixture a restored parse clause needs back. NO BULLET GLYPH on it: it is multibyte and
#   this suite runs under `set -u` on C-locale hosts. The HEADER, by contrast, is anchored
#   ^…$ in the shipped hook, so its two leading spaces are reproduced exactly.
mk_stub_semgrep() {
  mkdir -p "$1"
  { printf '#!/bin/sh\n'
    printf 'cat >&2 <<SOIFSTUBEOF\n'
    printf '  Scanning 1 file with %s\n' "$2"
    printf '  Parsed lines: %s\n' "$3"
    printf 'SOIFSTUBEOF\n'
    printf 'exit 0\n'
  } > "$1/semgrep"
  chmod +x "$1/semgrep"
}
# _stub_commit <stubdir> <hookfile> <log> -> COMMITTED|REFUSED|SETUPFAIL
#   ONE staged file, so the shipped `accepted >= ${#soif_idx_files[@]}` test compares 1
#   against 1 and the selection clause is satisfied on a WELL-FORMED banner — leaving the
#   header SPELLING as the only thing that can move the verdict.
_stub_commit() {
  local d; d="$(mktemp -d)"
  mk_repo "$d" "$2" >/dev/null 2>&1 || { rm -rf "$d"; echo SETUPFAIL; return; }
  printf '%s\n' "$SAFE_TS" > "$d/app.ts"
  ( cd "$d" && git add -- app.ts ) >/dev/null 2>&1
  if ( cd "$d" && PATH="$1:$PATH" git commit -m "feat: add a clean renderer" ) >"$3" 2>&1; then echo COMMITTED; else echo REFUSED; fi
  rm -rf "$d"
}

# ── T-scan-status-singular-rule (R-274Rv2-8: a measured permanent-NOTRUN cliff) ───
# The header parse hard-required the PLURAL `Code rules:` and semgrep really does print the
# singular: `semgrep scan --config=<one-rule.yml>` emits `Scanning 1 file with 1 Code rule:`
# on 1.157.0. A generated project whose resolved ruleset is one rule would therefore print
# `SAST NOT ENFORCED … CANNOT BE VERIFIED` on EVERY commit FOREVER — a permanent cliff, not
# a per-commit miss. Both spellings are accepted now; this pins that, and the mutant proves
# the cliff was real rather than hypothetical.
#   TWO ATOMS, PINNED BY THE TWO HALVES OF THIS CASE. The widening touched the counting
#   grep (`Code rules?:`) AND the extracting sed (`Code rules\{0,1\}:`), and a narrowing of
#   EITHER re-opens the cliff — an accepting grep with a rejecting sed still leaves
#   soif_sg_accepted empty. The GREEN half covers both: the receipt can only be earned if
#   the grep counts the header and the sed extracts its number. The RED half attacks the
#   grep specifically, to show the atom is decisive and not decoration.
echo "=== T-scan-status-singular-rule ==="
STUB1R="$TOPTMP/stub-1rule"
mk_stub_semgrep "$STUB1R" '1 Code rule:' '~100.0%'
SR_V="$(_stub_commit "$STUB1R" "$EMITTED" "$TOPTMP/sr-green")"
SRP="$TOPTMP/mut-plural-only"
if [ "$SR_V" = "SETUPFAIL" ]; then
  fail_ "T-scan-status-singular-rule" "fixture setup failed"
elif ! grep -qF '[OK] semgrep: SAST ran on 1 staged file(s)' "$TOPTMP/sr-green"; then
  fail_ "T-scan-status-singular-rule" "a single-rule resolved set makes EVERY commit a permanent NOTRUN — semgrep prints 'Scanning 1 file with 1 Code rule:' and the header parse rejected it: $(tail -6 "$TOPTMP/sr-green" | tr '\n' '|')"
elif ! _mut_n "$EMITTED" "$SRP" 'Code rules?:' 'Code rules:' 1; then
  fail_ "T-scan-status-singular-rule" "MIS-TARGETED — the header grep's rule-plural atom is not present exactly once in the emitted hook"
elif ! bash -n "$SRP" 2>/dev/null; then
  fail_ "T-scan-status-singular-rule" "mutated hook has a syntax error — a broken mutant proves nothing"
elif [ "$(_stub_commit "$STUB1R" "$SRP" "$TOPTMP/sr-red")" = "SETUPFAIL" ]; then
  fail_ "T-scan-status-singular-rule" "mutation fixture setup failed"
elif grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/sr-red"; then
  fail_ "T-scan-status-singular-rule" "narrowing the header grep back to the plural did NOT go RED — this case is not measuring the atom it names"
elif ! grep -qF 'CANNOT BE VERIFIED' "$TOPTMP/sr-red"; then
  fail_ "T-scan-status-singular-rule" "the plural-only mutant neither receipted nor reported an unverifiable header: $(tail -6 "$TOPTMP/sr-red" | tr '\n' '|')"
else
  pass "T-scan-status-singular-rule: 'Scanning 1 file with 1 Code rule:' EARNS the receipt; narrowing the grep back to the plural turns it into a permanent NOTRUN (RED) — the singular spelling is real and is now accepted (R-274Rv2-8)"
fi

# ═════════════════════════════════════════════════════════════════════════════════
# BL-198 — TRANSCODE-FIRST DECODE COVERAGE (# BL-198-TRANSCODE in the emitted hook).
# BL-192's gap: semgrep ACCEPTS a UTF-16 staged file, cannot decode it, scans it
# "clean", and the four-precondition receipt prints over an unseen sink — a positive
# false attestation. The fix classifies each materialized blob AFTER F2 (NUL scan →
# BOM longest-first → whole-file stride-aware zero-parity derivation, BOM and
# derivation required to AGREE), transcodes vouched UTF-16/UTF-32 to UTF-8 at the
# IDENTICAL tree path (temp + mv, never a redirect into the source), and fails
# CLOSED to a loud named NOTRUN on anything it cannot vouch. These cases are the
# fixture matrix from the BL-198 plan; five restore the shape of the cases withdrawn
# with the BL-186 parse clause (held on PR #278 @ e87dbd3), re-aimed off semgrep's
# self-report onto the transcode — the UTF-16 sink cases flip from "receipt
# forfeited" to the stronger "sink CAUGHT, commit BLOCKED".
#   Every fixture asserts its own byte shape (NUL count, BOM bytes, length parity)
#   before any behavior assertion, so a fixture edit cannot quietly turn a case
#   vacuous. A plain-UTF-8 control probe gates the sink cases: on a host where the
#   baseline sink does not block (no registry, rules unresolved), they SKIP as
#   UNPROVEN rather than mis-reporting the transcode.
# ═════════════════════════════════════════════════════════════════════════════════

HAVE_ICONV=0
command -v iconv >/dev/null 2>&1 && HAVE_ICONV=1

_bl198_nuls() {  # <file> -> count of NUL bytes
  local tot non
  tot=$(wc -c < "$1" 2>/dev/null | tr -d '[:space:]') || tot=0
  non=$(LC_ALL=C tr -d '\000' < "$1" 2>/dev/null | wc -c | tr -d '[:space:]') || non=0
  echo $(( tot - non ))
}

_bl198_head4() {  # <file> -> first 4 bytes as bare hex
  od -An -N4 -tx1 "$1" 2>/dev/null | tr -d ' \t\n'
}

_bl198_run() {  # <hookfile> <log> <relpath> <bytesfile> -> COMMITTED|REFUSED|SETUPFAIL
  local d v
  d="$(mktemp -d)"
  mk_repo "$d" "$1" >/dev/null 2>&1 || { rm -rf "$d"; echo SETUPFAIL; return; }
  cp "$4" "$d/$3" 2>/dev/null || { rm -rf "$d"; echo SETUPFAIL; return; }
  ( cd "$d" && git add -- "$3" ) >/dev/null 2>&1 || { rm -rf "$d"; echo SETUPFAIL; return; }
  if ( cd "$d" && git commit -m "feat: add module" ) >"$2" 2>&1; then v=COMMITTED; else v=REFUSED; fi
  rm -rf "$d"
  echo "$v"
}

BL198FIX="$TOPTMP/bl198fix"
mkdir -p "$BL198FIX"

# Control probe: the SAME sink in plain UTF-8 must block on this host, or the
# UTF-16 cases cannot distinguish "transcode failed" from "rules never resolved".
BL198_CONTROL=0
if [ "$HAVE_SEMGREP" -eq 1 ]; then
  printf '%s\n' "$REN_VULN" > "$BL198FIX/control.bin"
  BL198_CTL_V="$(_bl198_run "$EMITTED" "$TOPTMP/bl198-control" widget.ts "$BL198FIX/control.bin")"
  if [ "$BL198_CTL_V" = "REFUSED" ] && grep -qF '[BLOCKED] Semgrep' "$TOPTMP/bl198-control"; then
    BL198_CONTROL=1
  fi
fi

_bl198_skip_reason() {  # -> the reason the matrix cases cannot run, or empty
  if [ "$HAVE_SEMGREP" -eq 0 ]; then echo "semgrep ABSENT"; return; fi
  if [ "$HAVE_ICONV" -eq 0 ]; then echo "iconv ABSENT — cannot build UTF-16 fixtures"; return; fi
  if [ "$BL198_CONTROL" -eq 0 ]; then echo "plain-UTF-8 sink control did not BLOCK (registry unreachable?)"; fi
}

# ── T-utf16-parse-drop-no-receipt (restored from e87dbd3, RE-AIMED) ───────────────
# The original case pinned "receipt forfeited" via the withdrawn parse clause. The
# transcode buys the stronger DoD: the SAME fixture — an ordinary .ts saved as
# UTF-16LE WITH BOM, carrying the innerHTML sink — is now DECODED and its sink
# BLOCKS the commit outright.
echo "=== T-utf16-parse-drop-no-receipt ==="
BL198_WHY="$(_bl198_skip_reason)"
if [ -n "$BL198_WHY" ]; then
  skip_ "T-utf16-parse-drop-no-receipt" "$BL198_WHY — UNPROVEN here (skip, NOT a pass)"
else
  { printf '\xff\xfe'; printf '%s\n' "$REN_VULN" | iconv -f UTF-8 -t UTF-16LE; } > "$BL198FIX/le-bom.bin"
  if [ "$(_bl198_nuls "$BL198FIX/le-bom.bin")" -eq 0 ] || [ "$(_bl198_head4 "$BL198FIX/le-bom.bin" | cut -c1-4)" != "fffe" ]; then
    fail_ "T-utf16-parse-drop-no-receipt" "fixture is not BOM'd UTF-16LE (nuls=$(_bl198_nuls "$BL198FIX/le-bom.bin") head=$(_bl198_head4 "$BL198FIX/le-bom.bin")) — the case proves nothing"
  else
    U16A_V="$(_bl198_run "$EMITTED" "$TOPTMP/bl198-lebom" widget.ts "$BL198FIX/le-bom.bin")"
    if [ "$U16A_V" = "SETUPFAIL" ]; then
      fail_ "T-utf16-parse-drop-no-receipt" "fixture setup failed"
    elif [ "$U16A_V" = "REFUSED" ] && grep -qF '[BLOCKED] Semgrep' "$TOPTMP/bl198-lebom" \
         && ! grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/bl198-lebom"; then
      pass "T-utf16-parse-drop-no-receipt: a UTF-16LE+BOM staged sink is transcoded and BLOCKS — the BL-192 false attestation is gone and the DoD is the strong form"
    else
      fail_ "T-utf16-parse-drop-no-receipt" "verdict=$U16A_V — the sink in a UTF-16LE+BOM .ts did not block (BL-192: semgrep scans the undecoded bytes 'clean' and the receipt lies): $(sast_evidence "$TOPTMP/bl198-lebom")"
    fi
  fi
fi

# ── T-utf16le-nobom-sink-blocked (the decoy row: NO BOM, decodes as valid UTF-8) ──
# UTF-16LE without a BOM is the trap variant: the raw bytes happen to be valid
# UTF-8 (every other byte NUL), so any "is it valid UTF-8?" tightening waves it
# through. Whole-file zero-parity derivation is what catches it.
echo "=== T-utf16le-nobom-sink-blocked ==="
BL198_WHY="$(_bl198_skip_reason)"
if [ -n "$BL198_WHY" ]; then
  skip_ "T-utf16le-nobom-sink-blocked" "$BL198_WHY — UNPROVEN here (skip, NOT a pass)"
else
  printf '%s\n' "$REN_VULN" | iconv -f UTF-8 -t UTF-16LE > "$BL198FIX/le-nobom.bin"
  U16B_H="$(_bl198_head4 "$BL198FIX/le-nobom.bin" | cut -c1-4)"
  if [ "$(_bl198_nuls "$BL198FIX/le-nobom.bin")" -eq 0 ] || [ "$U16B_H" = "fffe" ]; then
    fail_ "T-utf16le-nobom-sink-blocked" "fixture is not BOM-less UTF-16LE (head=$U16B_H) — the case proves nothing"
  else
    U16B_V="$(_bl198_run "$EMITTED" "$TOPTMP/bl198-lenobom" widget.ts "$BL198FIX/le-nobom.bin")"
    if [ "$U16B_V" = "REFUSED" ] && grep -qF '[BLOCKED] Semgrep' "$TOPTMP/bl198-lenobom"; then
      pass "T-utf16le-nobom-sink-blocked: BOM-less UTF-16LE (raw bytes are VALID UTF-8 — the decoy) is parity-derived, transcoded, and its sink BLOCKS"
    else
      fail_ "T-utf16le-nobom-sink-blocked" "verdict=$U16B_V — the BOM-less UTF-16LE sink did not block: $(sast_evidence "$TOPTMP/bl198-lenobom")"
    fi
  fi
fi

# ── T-utf16be-sink-blocked (both BE variants: with and without BOM) ───────────────
echo "=== T-utf16be-sink-blocked ==="
BL198_WHY="$(_bl198_skip_reason)"
if [ -n "$BL198_WHY" ]; then
  skip_ "T-utf16be-sink-blocked" "$BL198_WHY — UNPROVEN here (skip, NOT a pass)"
else
  { printf '\xfe\xff'; printf '%s\n' "$REN_VULN" | iconv -f UTF-8 -t UTF-16BE; } > "$BL198FIX/be-bom.bin"
  printf '%s\n' "$REN_VULN" | iconv -f UTF-8 -t UTF-16BE > "$BL198FIX/be-nobom.bin"
  if [ "$(_bl198_head4 "$BL198FIX/be-bom.bin" | cut -c1-4)" != "feff" ] || [ "$(_bl198_nuls "$BL198FIX/be-nobom.bin")" -eq 0 ]; then
    fail_ "T-utf16be-sink-blocked" "BE fixtures malformed — the case proves nothing"
  else
    BE1_V="$(_bl198_run "$EMITTED" "$TOPTMP/bl198-bebom" widget.ts "$BL198FIX/be-bom.bin")"
    BE2_V="$(_bl198_run "$EMITTED" "$TOPTMP/bl198-benobom" widget.ts "$BL198FIX/be-nobom.bin")"
    if [ "$BE1_V" = "REFUSED" ] && grep -qF '[BLOCKED] Semgrep' "$TOPTMP/bl198-bebom" \
       && [ "$BE2_V" = "REFUSED" ] && grep -qF '[BLOCKED] Semgrep' "$TOPTMP/bl198-benobom"; then
      pass "T-utf16be-sink-blocked: UTF-16BE sinks block with a BOM (claim+derivation agree) and without one (derivation alone)"
    else
      fail_ "T-utf16be-sink-blocked" "BE+BOM=$BE1_V BE-noBOM=$BE2_V (both must REFUSE): $(sast_evidence "$TOPTMP/bl198-benobom")"
    fi
  fi
fi

# ── T-utf16-cjk-head-sink-blocked (the head-window refuter) ───────────────────────
# The file OPENS with a CJK comment block — UTF-16 code units with BOTH bytes
# non-zero, so a head-window sniff sees no NULs and reads "no signal" — and the
# ASCII sink sits after it. Whole-file parity must still catch it. (No BOM.)
echo "=== T-utf16-cjk-head-sink-blocked ==="
BL198_WHY="$(_bl198_skip_reason)"
if [ -n "$BL198_WHY" ]; then
  skip_ "T-utf16-cjk-head-sink-blocked" "$BL198_WHY — UNPROVEN here (skip, NOT a pass)"
else
  { printf '// %s\n' "中文注释中文注释中文注释中文注释中文注释中文注释中文注释中文注释"; printf '%s\n' "$REN_VULN"; } | iconv -f UTF-8 -t UTF-16LE > "$BL198FIX/cjk-head.bin"
  if [ "$(_bl198_nuls "$BL198FIX/cjk-head.bin")" -eq 0 ]; then
    fail_ "T-utf16-cjk-head-sink-blocked" "fixture carries no NULs at all — it is not the shape this case names"
  else
    CJK_V="$(_bl198_run "$EMITTED" "$TOPTMP/bl198-cjk" widget.ts "$BL198FIX/cjk-head.bin")"
    if [ "$CJK_V" = "REFUSED" ] && grep -qF '[BLOCKED] Semgrep' "$TOPTMP/bl198-cjk"; then
      pass "T-utf16-cjk-head-sink-blocked: a CJK-opening UTF-16 file is parity-read over the WHOLE file and its sink blocks — no head window to fool"
    else
      fail_ "T-utf16-cjk-head-sink-blocked" "verdict=$CJK_V — the CJK-head UTF-16 sink did not block: $(sast_evidence "$TOPTMP/bl198-cjk")"
    fi
  fi
fi

# ── T-parse-threshold-exact (restored from e87dbd3, RE-AIMED at BOM order) ────────
# The original pinned an exact `-ge 100` threshold. The transcode design has no
# ratio (the parity rule is all-zeros-on-one-parity, exact by construction); the
# boundary that CAN silently re-narrow is the BOM match ORDER — `FF FE` is a
# PREFIX of the UTF-32LE BOM, so longest-first is load-bearing. A UTF-32LE+BOM
# sink must be read as UTF-32LE and block; shortest-first would misread it as
# UTF-16LE, fail the output vouch, and cry wolf on a legitimate file.
echo "=== T-parse-threshold-exact ==="
BL198_WHY="$(_bl198_skip_reason)"
if [ -n "$BL198_WHY" ]; then
  skip_ "T-parse-threshold-exact" "$BL198_WHY — UNPROVEN here (skip, NOT a pass)"
else
  { printf '\xff\xfe\x00\x00'; printf '%s\n' "$REN_VULN" | iconv -f UTF-8 -t UTF-32LE; } > "$BL198FIX/u32le-bom.bin"
  if [ "$(_bl198_head4 "$BL198FIX/u32le-bom.bin")" != "fffe0000" ]; then
    fail_ "T-parse-threshold-exact" "fixture head is not the UTF-32LE BOM — the case proves nothing"
  else
    U32_V="$(_bl198_run "$EMITTED" "$TOPTMP/bl198-u32" widget.ts "$BL198FIX/u32le-bom.bin")"
    if [ "$U32_V" = "REFUSED" ] && grep -qF '[BLOCKED] Semgrep' "$TOPTMP/bl198-u32"; then
      pass "T-parse-threshold-exact: a UTF-32LE+BOM sink is matched longest-first, transcoded as UTF-32LE, and BLOCKS"
    else
      fail_ "T-parse-threshold-exact" "verdict=$U32_V — the UTF-32LE+BOM sink did not block (BOM order or stride derivation broken): $(sast_evidence "$TOPTMP/bl198-u32")"
    fi
  fi
fi

# ── T-utf16-lying-bom-notrun (the agree-check, BOTH directions) ───────────────────
# A BOM is a CLAIM. `FF FE` (claims LE) over a UTF-16BE body transcodes to
# NUL-free valid-UTF-8 GARBAGE that passes every output check — so without the
# claim/derivation agree-check the fix itself mints a fresh false receipt. Both
# lying directions must land as a LOUD named NOTRUN: never scanned-clean, never
# blocked, never receipted.
echo "=== T-utf16-lying-bom-notrun ==="
BL198_WHY="$(_bl198_skip_reason)"
if [ -n "$BL198_WHY" ]; then
  skip_ "T-utf16-lying-bom-notrun" "$BL198_WHY — UNPROVEN here (skip, NOT a pass)"
else
  { printf '\xff\xfe'; printf '%s\n' "$REN_VULN" | iconv -f UTF-8 -t UTF-16BE; } > "$BL198FIX/lie-le-over-be.bin"
  { printf '\xfe\xff'; printf '%s\n' "$REN_VULN" | iconv -f UTF-8 -t UTF-16LE; } > "$BL198FIX/lie-be-over-le.bin"
  LIE1_V="$(_bl198_run "$EMITTED" "$TOPTMP/bl198-lie1" widget.ts "$BL198FIX/lie-le-over-be.bin")"
  LIE2_V="$(_bl198_run "$EMITTED" "$TOPTMP/bl198-lie2" widget.ts "$BL198FIX/lie-be-over-le.bin")"
  LIE_OK=1
  for LIE_LOG in "$TOPTMP/bl198-lie1" "$TOPTMP/bl198-lie2"; do
    if ! grep -qF 'SAST NOT ENFORCED' "$LIE_LOG" || ! grep -qF 'widget.ts' "$LIE_LOG" \
       || grep -qF '[OK] semgrep: SAST ran' "$LIE_LOG"; then LIE_OK=0; fi
  done
  if [ "$LIE1_V" = "COMMITTED" ] && [ "$LIE2_V" = "COMMITTED" ] && [ "$LIE_OK" -eq 1 ]; then
    pass "T-utf16-lying-bom-notrun: both lying-BOM directions land as a LOUD NOTRUN that NAMES widget.ts — no receipt over garbage, no block on an unvouchable read"
  else
    fail_ "T-utf16-lying-bom-notrun" "lie1=$LIE1_V lie2=$LIE2_V named-and-unreceipted=$LIE_OK — a lying BOM must forfeit the receipt and name the file, in both directions: $(sast_evidence "$TOPTMP/bl198-lie1")"
  fi
fi

# ── T-parse-coverage-fails-closed (restored from e87dbd3, RE-AIMED at iconv) ──────
# The original pinned the withdrawn clause's unreadable-banner arm. Re-aimed: a
# vouched-looking file iconv still cannot convert — BOM'd UTF-16LE with an
# UNPAIRED HIGH SURROGATE (U+D834 with no low half) — must fail CLOSED: iconv
# exits non-zero, the raw bytes stay intact, the receipt is forfeited, the file
# is NAMED, and the commit lands as a WARN (an unconvertible file is not
# evidence of a defect).
echo "=== T-parse-coverage-fails-closed ==="
BL198_WHY="$(_bl198_skip_reason)"
if [ -n "$BL198_WHY" ]; then
  skip_ "T-parse-coverage-fails-closed" "$BL198_WHY — UNPROVEN here (skip, NOT a pass)"
else
  { printf '\xff\xfe'; printf 'const a = "x";\n' | iconv -f UTF-8 -t UTF-16LE; printf '\x34\xd8'; printf 'const b = "y";\n' | iconv -f UTF-8 -t UTF-16LE; } > "$BL198FIX/surrogate.bin"
  if iconv -f UTF-16LE -t UTF-8 "$BL198FIX/surrogate.bin" >/dev/null 2>&1; then
    skip_ "T-parse-coverage-fails-closed" "this host's iconv ACCEPTS an unpaired surrogate — the iconv-failure path is unreachable with this fixture here (skip, NOT a pass)"
  else
    SUR_V="$(_bl198_run "$EMITTED" "$TOPTMP/bl198-sur" widget.ts "$BL198FIX/surrogate.bin")"
    if [ "$SUR_V" = "COMMITTED" ] && grep -qF 'SAST NOT ENFORCED' "$TOPTMP/bl198-sur" \
       && grep -qF 'widget.ts' "$TOPTMP/bl198-sur" \
       && ! grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/bl198-sur"; then
      pass "T-parse-coverage-fails-closed: an unconvertible (unpaired-surrogate) UTF-16 file forfeits the receipt LOUDLY, names the file, and never mints [OK]"
    else
      fail_ "T-parse-coverage-fails-closed" "verdict=$SUR_V — iconv failure must be a loud named NOTRUN, never a receipt: $(sast_evidence "$TOPTMP/bl198-sur")"
    fi
  fi
fi

# ── T-utf16-clean-transcode-receipt (the receipt names the transcode) ─────────────
echo "=== T-utf16-clean-transcode-receipt ==="
BL198_WHY="$(_bl198_skip_reason)"
if [ -n "$BL198_WHY" ]; then
  skip_ "T-utf16-clean-transcode-receipt" "$BL198_WHY — UNPROVEN here (skip, NOT a pass)"
else
  { printf '\xff\xfe'; printf '%s\n' "$SAFE_TS" | iconv -f UTF-8 -t UTF-16LE; } > "$BL198FIX/le-clean.bin"
  CLN_V="$(_bl198_run "$EMITTED" "$TOPTMP/bl198-clean" widget.ts "$BL198FIX/le-clean.bin")"
  if [ "$CLN_V" = "COMMITTED" ] && grep -qF '[OK] semgrep: SAST ran on 1 staged file(s)' "$TOPTMP/bl198-clean" \
     && grep -qE 'transcoded' "$TOPTMP/bl198-clean"; then
    pass "T-utf16-clean-transcode-receipt: a CLEAN UTF-16 file earns the receipt AND the receipt says it was transcoded — the conversion is attested, not silent"
  else
    fail_ "T-utf16-clean-transcode-receipt" "verdict=$CLN_V — a clean UTF-16 commit must earn a receipt that NAMES the transcode: $(sast_evidence "$TOPTMP/bl198-clean")"
  fi
fi

# ── T-utf8-bom-passthrough + T-latin1-passthrough (must NOT be touched) ───────────
# UTF-8+BOM is legal and common from Windows editors; Latin-1 is NUL-free and
# invalid UTF-8 and semgrep handles it (measured in the plan's review) — the
# classifier must pass BOTH through untouched with the receipt intact. Latin-1 is
# also why "NUL-free AND valid UTF-8" is the WRONG tightening.
echo "=== T-utf8-bom-and-latin1-passthrough ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-utf8-bom-and-latin1-passthrough" "semgrep ABSENT — UNPROVEN here (skip, NOT a pass)"
else
  { printf '\xef\xbb\xbf'; printf '%s\n' "$SAFE_TS"; } > "$BL198FIX/u8bom.bin"
  printf 'const cafe = "caf\xe9";\nexport const n = 1;\n' > "$BL198FIX/latin1.bin"
  if [ "$(_bl198_nuls "$BL198FIX/u8bom.bin")" -ne 0 ] || [ "$(_bl198_nuls "$BL198FIX/latin1.bin")" -ne 0 ]; then
    fail_ "T-utf8-bom-and-latin1-passthrough" "passthrough fixtures unexpectedly carry NULs — wrong shape"
  else
    U8_V="$(_bl198_run "$EMITTED" "$TOPTMP/bl198-u8bom" widget.ts "$BL198FIX/u8bom.bin")"
    L1_V="$(_bl198_run "$EMITTED" "$TOPTMP/bl198-latin1" widget.ts "$BL198FIX/latin1.bin")"
    if [ "$U8_V" = "COMMITTED" ] && grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/bl198-u8bom" \
       && ! grep -qE 'transcoded' "$TOPTMP/bl198-u8bom" \
       && [ "$L1_V" = "COMMITTED" ] && grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/bl198-latin1" \
       && ! grep -qE 'transcoded' "$TOPTMP/bl198-latin1"; then
      pass "T-utf8-bom-and-latin1-passthrough: UTF-8+BOM and Latin-1 sources pass through untouched and still earn the receipt — no transcode, no cry-wolf"
    else
      fail_ "T-utf8-bom-and-latin1-passthrough" "u8bom=$U8_V latin1=$L1_V — NUL-free files must be untouched with receipts intact: $(sast_evidence "$TOPTMP/bl198-latin1")"
    fi
  fi
fi

# ── T-binary-passthrough-receipt (WP4's binary-commit case) ───────────────────────
# A real binary (PNG magic + NULs, non-source extension) staged beside a clean .ts:
# no transcode attempt, no block, and the commit LANDS exactly as it does today.
echo "=== T-binary-passthrough-receipt ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-binary-passthrough-receipt" "semgrep ABSENT — UNPROVEN here (skip, NOT a pass)"
else
  _bl198_bin_commit() {  # <hookfile> <log> -> COMMITTED|REFUSED|SETUPFAIL
    local d; d="$(mktemp -d)"
    mk_repo "$d" "$1" >/dev/null 2>&1 || { rm -rf "$d"; echo SETUPFAIL; return; }
    printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde' > "$d/logo.png"
    printf '%s\n' "$SAFE_TS" > "$d/app.ts"
    ( cd "$d" && git add -- logo.png app.ts ) >/dev/null 2>&1
    if ( cd "$d" && git commit -m "feat: add renderer and logo" ) >"$2" 2>&1; then echo COMMITTED; else echo REFUSED; fi
    rm -rf "$d"
  }
  BIN_V="$(_bl198_bin_commit "$EMITTED" "$TOPTMP/bl198-bin")"
  if [ "$BIN_V" = "COMMITTED" ] && ! grep -qE 'transcoded' "$TOPTMP/bl198-bin" \
     && ! grep -qF '[BLOCKED] Semgrep' "$TOPTMP/bl198-bin"; then
    pass "T-binary-passthrough-receipt: a PNG (NULs, no BOM, no parity signal, non-source extension) rides along untouched — no transcode attempt, no block, commit lands"
  else
    fail_ "T-binary-passthrough-receipt" "verdict=$BIN_V — a binary sibling must neither transcode nor block: $(sast_evidence "$TOPTMP/bl198-bin")"
  fi
fi

# ── T-pure-cjk-residue-passthrough (the NAMED residue, pinned as documentation) ───
# A single-line zero-ASCII pure-CJK UTF-16 file has NO NUL anywhere (every code
# unit is two non-zero bytes), so WP0.1 passes it through and semgrep scans it
# undecoded. This is the plan's DOCUMENTED residue (review R3-2), bounded to
# zero-ASCII single-line files, and deliberately NOT closed at the BYTE layer:
# the only tightening that would catch it there also breaks Latin-1 passthrough.
# The case pins the boundary so a future "fix" that silently widens or narrows
# it shows up here.
#   THE RECEIPT HALF IS A MEASURED DISJUNCTION SINCE BL-200. The passthrough
#   facts are HARD pins (no transcode, no block, commit lands). What the receipt
#   then says depends on whether the HOST semgrep emits its syntax-error warning
#   while chewing the undecoded bytes: where it does (measured on 1.157.0), the
#   BL-200 detector forfeits the receipt and the residue no longer buys an
#   unearned [OK] — a strict narrowing, best-effort by BL-200's own terms; where
#   it stays silent, the pre-BL-200 receipt shape stands, which is the residue
#   as BL-198 documented it. BOTH arms are named; anything else — a block, a
#   transcode, a forfeit with no BL-200 warn — is a moved boundary and fails.
echo "=== T-pure-cjk-residue-passthrough ==="
BL198_WHY="$(_bl198_skip_reason)"
if [ -n "$BL198_WHY" ]; then
  skip_ "T-pure-cjk-residue-passthrough" "$BL198_WHY — UNPROVEN here (skip, NOT a pass)"
else
  printf '%s' "中文注释中文注释中文注释中文注释" | iconv -f UTF-8 -t UTF-16LE > "$BL198FIX/purecjk.bin"
  if [ "$(_bl198_nuls "$BL198FIX/purecjk.bin")" -ne 0 ]; then
    fail_ "T-pure-cjk-residue-passthrough" "fixture carries a NUL — it is not the zero-ASCII shape the residue names"
  else
    CJ2_V="$(_bl198_run "$EMITTED" "$TOPTMP/bl198-purecjk" widget.ts "$BL198FIX/purecjk.bin")"
    if [ "$CJ2_V" != "COMMITTED" ] || grep -qE 'transcoded' "$TOPTMP/bl198-purecjk" \
       || grep -qF '[BLOCKED] Semgrep' "$TOPTMP/bl198-purecjk"; then
      fail_ "T-pure-cjk-residue-passthrough" "verdict=$CJ2_V — the PASSTHROUGH boundary moved (no transcode, no block, commit lands are the hard pins; this case exists to make movement loud): $(sast_evidence "$TOPTMP/bl198-purecjk")"
    elif grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/bl198-purecjk"; then
      pass "T-pure-cjk-residue-passthrough: passthrough intact and the receipt is GRANTED — this host's semgrep is silent on the undecoded bytes, the residue stands exactly as BL-198 documented it"
    elif grep -qF 'token-stream break' "$TOPTMP/bl198-purecjk"; then
      pass "T-pure-cjk-residue-passthrough: passthrough intact and the receipt is FORFEITED by the BL-200 warn — this host's semgrep chokes loudly on the undecoded bytes, so the residue no longer buys an unearned [OK] (a strict, best-effort narrowing)"
    else
      fail_ "T-pure-cjk-residue-passthrough" "the receipt was withheld with NO BL-200 token-stream warn — neither documented arm; the boundary moved somewhere new: $(sast_evidence "$TOPTMP/bl198-purecjk")"
    fi
  fi
fi

# ── T-u32bom-over-u16-body-notrun (review R-BL198-1 — the stride-shift liar) ──────
# A UTF-32LE BOM (FF FE 00 00) prefixed to a UTF-16LE body: the 4-byte shift puts a
# zero on every position ≡3 (mod 4), so the naive stride-4 derivation AGREES with
# the lie (z[3]==n/4 exactly), macOS libiconv then accepts the out-of-range code
# points a real UTF-32 read of UTF-16 bytes produces, and the output is NUL-free —
# all three vouching surfaces defeated, [OK] receipt over a live sink (reproduced
# end-to-end in review). The U+10FFFF range bound closes it: in genuine UTF-32LE
# byte@2 of every group is <= 0x10 (and byte@1 for BE) — exact for BMP AND astral —
# while the shifted UTF-16 body carries ordinary ASCII there. Expect: loud named
# NOTRUN, no receipt, no block, commit lands.
echo "=== T-u32bom-over-u16-body-notrun ==="
BL198_WHY="$(_bl198_skip_reason)"
if [ -n "$BL198_WHY" ]; then
  skip_ "T-u32bom-over-u16-body-notrun" "$BL198_WHY — UNPROVEN here (skip, NOT a pass)"
else
  { printf '\xff\xfe\x00\x00'; printf '%s\n' "$REN_VULN" | iconv -f UTF-8 -t UTF-16LE; } > "$BL198FIX/u32lie.bin"
  if [ "$(_bl198_head4 "$BL198FIX/u32lie.bin")" != "fffe0000" ]; then
    fail_ "T-u32bom-over-u16-body-notrun" "fixture head is not the UTF-32LE BOM — the case proves nothing"
  else
    U32L_V="$(_bl198_run "$EMITTED" "$TOPTMP/bl198-u32lie" widget.ts "$BL198FIX/u32lie.bin")"
    if [ "$U32L_V" = "COMMITTED" ] && grep -qF 'SAST NOT ENFORCED' "$TOPTMP/bl198-u32lie" \
       && grep -qF 'widget.ts' "$TOPTMP/bl198-u32lie" \
       && ! grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/bl198-u32lie" \
       && ! grep -qF '[BLOCKED] Semgrep' "$TOPTMP/bl198-u32lie"; then
      pass "T-u32bom-over-u16-body-notrun: a stride-4 BOM over a stride-2 body is caught by the U+10FFFF range bound — loud named NOTRUN, never a receipt over garbage (R-BL198-1)"
    else
      fail_ "T-u32bom-over-u16-body-notrun" "verdict=$U32L_V — the stride-shift liar must be a loud named NOTRUN (a receipt here is the BL-192 false attestation reborn through the fix itself): $(sast_evidence "$TOPTMP/bl198-u32lie")"
    fi
  fi
fi

# ── T-u16-wrongparity-residue (review R-BL198-2 — the THIRD residue, pinned) ──────
# One code unit whose LOW byte is 0x00 — U+3000 ideographic space, U+0100 Ā, any
# astral char with a zero surrogate byte (U+1F600) — puts a single zero on the
# wrong parity and collapses the all-zeros-on-one-parity signal: the file goes
# LOUD named NOTRUN, forever. This is deliberate and pinned AS the boundary:
# relaxing to a dominance ratio would let a CRAFTED no-BOM file steer the
# derivation to the wrong endianness, whose transcode is NUL-free valid-UTF-8
# garbage — a receipt over an unscanned sink, the strictly worse failure. Exact
# stays; the cost is this loud residue (named in the plan and the fence comment).
echo "=== T-u16-wrongparity-residue ==="
BL198_WHY="$(_bl198_skip_reason)"
if [ -n "$BL198_WHY" ]; then
  skip_ "T-u16-wrongparity-residue" "$BL198_WHY — UNPROVEN here (skip, NOT a pass)"
else
  printf 'const pad = "\343\200\200";\nexport const n = 1;\n' | iconv -f UTF-8 -t UTF-16LE > "$BL198FIX/wrongparity.bin"
  WP_EVEN_ZEROS=$(od -An -v -tx1 "$BL198FIX/wrongparity.bin" | awk '{ for (i = 1; i <= NF; i++) { if ($i == "00" && n % 2 == 0) e++; n++ } } END { print e + 0 }')
  if [ "${WP_EVEN_ZEROS:-0}" -eq 0 ]; then
    fail_ "T-u16-wrongparity-residue" "fixture has no wrong-parity zero (U+3000 low byte) — it is not the residue shape"
  else
    WPR_V="$(_bl198_run "$EMITTED" "$TOPTMP/bl198-wrongparity" widget.ts "$BL198FIX/wrongparity.bin")"
    if [ "$WPR_V" = "COMMITTED" ] && grep -qF 'SAST NOT ENFORCED' "$TOPTMP/bl198-wrongparity" \
       && grep -qF 'widget.ts' "$TOPTMP/bl198-wrongparity" \
       && ! grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/bl198-wrongparity"; then
      pass "T-u16-wrongparity-residue: a clean UTF-16LE file with one U+3000 is a LOUD named NOTRUN — the exactness residue is real, bounded, and pinned (R-BL198-2; dominance was rejected because it reopens crafted mis-derivation)"
    else
      fail_ "T-u16-wrongparity-residue" "verdict=$WPR_V — the wrong-parity residue boundary moved (this case exists to make that loud): $(sast_evidence "$TOPTMP/bl198-wrongparity")"
    fi
  fi
fi

# ── T-utf8-floor-no-sigpipe (review R-BL198-6 — the BL-183 class, same file) ──────
# The transcode-output byte floor is a `od | awk` pipeline under the hook's
# `set -euo pipefail`. An `exit` in awk's MAIN rule SIGPIPEs od on input past the
# pipe buffer: rc 141, and the `|| soif_tc_badbyte=""` guard ERASES the detection
# awk just printed — the floor fails OPEN as a pure function of file size
# (threshold ~1-8 KB; measured in review with awk printing 'bad' every time).
# No live path reaches the floor today (R-BL198-1's bound caps code points at
# U+10FFFF), which is exactly why it must work: it is the surface that catches a
# future weakening of surface 1. Both spellings run here against a >100 KB
# bad-byte-FIRST fixture (the T-predicate-no-sigpipe pattern from bl118/bl131),
# plus a spelling pin on the emitted hook so the shipped floor cannot quietly
# revert to the early-exit form. LOCKSTEP: the two awk programs below must match
# the emitted hook's floor line (# BL-198 comment block, soif_tc_badbyte).
echo "=== T-utf8-floor-no-sigpipe ==="
FLOOR_FIX="$TOPTMP/floor-fixture.bin"
{ printf '\xf5'; awk 'BEGIN { for (i = 0; i < 8000; i++) print "abcdefghijklm" }'; } > "$FLOOR_FIX"
FLOOR_SZ=$(wc -c < "$FLOOR_FIX" | tr -d '[:space:]')
if [ "${FLOOR_SZ:-0}" -lt 100000 ]; then
  fail_ "T-utf8-floor-no-sigpipe" "fixture too small to force the race ($FLOOR_SZ < 100000) — the case is VACUOUS"
elif [ "$(grep -c 'soif_tc_badbyte=' "$EMITTED")" -ne 1 ]; then
  fail_ "T-utf8-floor-no-sigpipe" "the floor assignment line is not present exactly once in the emitted hook (assignment + its || reset share the line) — retarget this pin in lockstep"
else
  _floor_old() {  # the early-exit spelling (MUST miss on the big fixture under pipefail)
    ( set -euo pipefail
      v=$(od -An -v -tx1 "$FLOOR_FIX" 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i >= "f5") { print "bad"; exit } }') || v=""
      [ -n "$v" ] && echo DETECTED || echo MISSED ) 2>/dev/null
  }
  _floor_new() {  # the full-input-consumer spelling (MUST detect at every size)
    ( set -euo pipefail
      v=$(od -An -v -tx1 "$FLOOR_FIX" 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i >= "f5") b = 1 } END { if (b) print "bad" }') || v=""
      [ -n "$v" ] && echo DETECTED || echo MISSED ) 2>/dev/null
  }
  FLOOR_OLD_V="$(_floor_old)"
  FLOOR_NEW_V="$(_floor_new)"
  if [ "$FLOOR_OLD_V" != "MISSED" ]; then
    fail_ "T-utf8-floor-no-sigpipe" "the early-exit spelling did NOT miss on a $FLOOR_SZ-byte bad-first fixture (got $FLOOR_OLD_V) — the fixture no longer forces the race, so the case proves nothing"
  elif [ "$FLOOR_NEW_V" != "DETECTED" ]; then
    fail_ "T-utf8-floor-no-sigpipe" "the END-form spelling MISSED the bad byte — the fixed floor does not detect"
  elif grep -qF 'if ($i >= "f5") { print "bad"; exit }' "$EMITTED"; then
    fail_ "T-utf8-floor-no-sigpipe" "the emitted hook still carries the early-exit floor spelling — the SIGPIPE class is live in the shipped bytes (R-BL198-6)"
  elif ! grep -qF 'if ($i >= "f5") b = 1 } END { if (b) print "bad" }' "$EMITTED"; then
    fail_ "T-utf8-floor-no-sigpipe" "the emitted hook does not carry the END-form floor spelling — the lockstep pin lost its target; retarget in lockstep"
  else
    pass "T-utf8-floor-no-sigpipe: the early-exit floor misses a $FLOOR_SZ-byte bad-first output under pipefail while the shipped END-form detects it — the defense-in-depth surface actually defends (R-BL198-6, the BL-183 class)"
  fi
fi

# ── T-mutation-parse-coverage (restored from e87dbd3, RE-AIMED at the fence) ──────
# Excise the whole # BL-198-TRANSCODE fence from the emitted hook -> the BL-192
# false attestation RETURNS (UTF-16LE+BOM sink lands with the [OK] receipt) — RED.
# The unmutated hook REFUSES the same fixture — GREEN. Both directions run here so
# the case is an honest standalone verdict.
echo "=== T-mutation-parse-coverage ==="
BL198_WHY="$(_bl198_skip_reason)"
if [ -n "$BL198_WHY" ]; then
  skip_ "T-mutation-parse-coverage" "$BL198_WHY — mutation UNPROVEN here (skip, NOT a pass)"
else
  MTC="$TOPTMP/mut-transcode"
  MTC_B=$(grep -c '# BL-198-TRANSCODE-BEGIN' "$EMITTED") || MTC_B=0
  MTC_E=$(grep -c '# BL-198-TRANSCODE-END' "$EMITTED") || MTC_E=0
  sed '/# BL-198-TRANSCODE-BEGIN/,/# BL-198-TRANSCODE-END/d' "$EMITTED" > "$MTC"
  # Count only the fence MARKERS left — the init comment outside the fence
  # legitimately names BL-198-TRANSCODE and must survive the excision.
  MTC_LEFT=$(grep -cE 'BL-198-TRANSCODE-(BEGIN|END)' "$MTC") || MTC_LEFT=0
  if [ "$MTC_B" -ne 1 ] || [ "$MTC_E" -ne 1 ] || [ "$MTC_LEFT" -ne 0 ]; then
    fail_ "T-mutation-parse-coverage" "MIS-TARGETED — fence not present exactly once (begin=$MTC_B end=$MTC_E left=$MTC_LEFT); retarget this mutation in lockstep"
  elif ! bash -n "$MTC" 2>/dev/null; then
    fail_ "T-mutation-parse-coverage" "mutated hook has a syntax error — a broken mutant proves nothing"
  else
    chmod +x "$MTC"
    MTC_RED="$(_bl198_run "$MTC" "$TOPTMP/bl198-mut-red" widget.ts "$BL198FIX/le-bom.bin")"
    MTC_GRN="$(_bl198_run "$EMITTED" "$TOPTMP/bl198-mut-grn" widget.ts "$BL198FIX/le-bom.bin")"
    # RED SINCE BL-200: the excision no longer buys the FULL BL-192 false
    # attestation on every host, because the syntax detector is an INDEPENDENT
    # second layer — on a semgrep that warns while chewing the undecoded bytes
    # (measured on 1.157.0) the receipt is forfeited even with the fence gone.
    # What the excision provably loses on EVERY host is the BLOCK: only the
    # transcode makes the sink VISIBLE, so the mutant commit LANDS (the harm)
    # while the shipped hook REFUSES it. The receipt half is the same measured
    # disjunction as T-pure-cjk-residue-passthrough: granted (detector-silent
    # host — the original false attestation) or forfeited WITH the BL-200 warn
    # (defense-in-depth degrading safely); anything else fails.
    if [ "$MTC_RED" != "COMMITTED" ] || grep -qF '[BLOCKED] Semgrep' "$TOPTMP/bl198-mut-red" \
       || [ "$MTC_GRN" != "REFUSED" ] || ! grep -qF '[BLOCKED] Semgrep' "$TOPTMP/bl198-mut-grn"; then
      fail_ "T-mutation-parse-coverage" "expected RED=COMMITTED(sink lands, unblocked) / GREEN=REFUSED+blocked; got RED=$MTC_RED GREEN=$MTC_GRN — the fence's blocking power is the hard pin: $(sast_evidence "$TOPTMP/bl198-mut-red")"
    elif grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/bl198-mut-red"; then
      pass "T-mutation-parse-coverage: excising the # BL-198-TRANSCODE fence lands the sink WITH the full BL-192 false receipt on this host (RED), the shipped hook blocks it (GREEN) — the fence is load-bearing"
    elif grep -qF 'token-stream break' "$TOPTMP/bl198-mut-red"; then
      pass "T-mutation-parse-coverage: excising the # BL-198-TRANSCODE fence lands the sink (RED — the harm survives excision) but the BL-200 detector independently forfeits the receipt on this host (defense-in-depth: the excision degrades to a loud forfeit, not a false attestation); the shipped hook blocks it (GREEN) — the fence carries the BLOCK"
    else
      fail_ "T-mutation-parse-coverage" "the mutant's receipt was withheld with NO BL-200 warn — neither documented arm; something else moved: $(sast_evidence "$TOPTMP/bl198-mut-red")"
    fi
  fi
fi

# ── T-mutation-parse-threshold (restored from e87dbd3, RE-AIMED at BOM order) ─────
# Swap the BOM match so the UTF-16LE prefix is tested BEFORE the UTF-32LE BOM —
# the one-character-narrowing analogue for this classifier. The UTF-32LE+BOM sink
# then derives stride-2 (a UTF-32 file carries zeros on BOTH 2-byte parities), the
# claim/derivation agree-check fails, and the file degrades to a LOUD cry-wolf
# NOTRUN instead of a caught sink (RED). The shipped order transcodes and BLOCKS
# (GREEN). Degrading SAFELY is exactly why this is a mutation case and not a hole:
# the failure direction is a false WARN, never a false receipt.
echo "=== T-mutation-parse-threshold ==="
BL198_WHY="$(_bl198_skip_reason)"
if [ -n "$BL198_WHY" ]; then
  skip_ "T-mutation-parse-threshold" "$BL198_WHY — mutation UNPROVEN here (skip, NOT a pass)"
else
  MBO="$TOPTMP/mut-bomorder"
  MBO_N=$(grep -c 'fffe0000\*) soif_tc_bom="UTF-32LE" ;;' "$EMITTED") || MBO_N=0
  awk '
    /fffe0000\*\) soif_tc_bom="UTF-32LE" ;;/ { print "          fffe*)     soif_tc_bom=\"UTF-16LE\" ;;"; print; next }
    /fffe\*\)     soif_tc_bom="UTF-16LE" ;;/ { next }
    { print }' "$EMITTED" > "$MBO"
  if [ "$MBO_N" -ne 1 ] || ! grep -qF 'fffe*)' "$MBO" || cmp -s "$EMITTED" "$MBO"; then
    fail_ "T-mutation-parse-threshold" "MIS-TARGETED — could not reorder the BOM arms (n=$MBO_N, identical=$(cmp -s "$EMITTED" "$MBO" && echo yes || echo no)); retarget this mutation in lockstep"
  elif ! bash -n "$MBO" 2>/dev/null; then
    fail_ "T-mutation-parse-threshold" "mutated hook has a syntax error — a broken mutant proves nothing"
  else
    chmod +x "$MBO"
    MBO_RED="$(_bl198_run "$MBO" "$TOPTMP/bl198-bom-red" widget.ts "$BL198FIX/u32le-bom.bin")"
    MBO_GRN="$(_bl198_run "$EMITTED" "$TOPTMP/bl198-bom-grn" widget.ts "$BL198FIX/u32le-bom.bin")"
    if [ "$MBO_RED" = "COMMITTED" ] && grep -qF 'SAST NOT ENFORCED' "$TOPTMP/bl198-bom-red" \
       && ! grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/bl198-bom-red" \
       && [ "$MBO_GRN" = "REFUSED" ] && grep -qF '[BLOCKED] Semgrep' "$TOPTMP/bl198-bom-grn"; then
      pass "T-mutation-parse-threshold: shortest-first BOM order degrades the UTF-32LE sink to a cry-wolf NOTRUN (RED, safe direction) and longest-first catches it (GREEN) — the order is load-bearing (was: the -ge 100 exact-threshold proof)"
    else
      fail_ "T-mutation-parse-threshold" "expected RED=COMMITTED+NOTRUN-no-receipt / GREEN=REFUSED+blocked; got RED=$MBO_RED GREEN=$MBO_GRN: $(sast_evidence "$TOPTMP/bl198-bom-red")"
    fi
  fi
fi

# ── T-ext-set-pinned (the WP0.4 drift tripwire — its failure mode is fail-OPEN) ───
# The NULs+no-BOM+no-signal branch routes LOUD only for extensions in the
# # BL-198-EXT-SET literal; an extension missing from it passes through instead —
# fail-open by design (real binaries must pass), so drift is silent. Two pins:
# (1) STATIC — every extension in the BL-125 test arm's source list (the house
# definition of "source") must appear in the hook's BL-198-EXT-SET literal;
# (2) BEHAVIORAL — a both-parities NUL file (no BOM, no derivable signal) with a
# source extension lands as a LOUD named NOTRUN, never a receipt.
echo "=== T-ext-set-pinned ==="
EXT_LINE=$(grep -A2 '# BL-198-EXT-SET' "$EMITTED" | grep '\*\.' | head -1)
TESTARM_EXTS=$(grep -oE '\\.\(([a-z|]+)\)\$' "$EMITTED" | head -1 | sed 's/^\\\.(//; s/)\$//')
if [ -z "$EXT_LINE" ] || [ -z "$TESTARM_EXTS" ]; then
  fail_ "T-ext-set-pinned" "could not extract the BL-198-EXT-SET case line or the BL-125 test-arm extension list from the emitted hook — retarget this pin in lockstep"
else
  EXT_MISSING=""
  for EXT in $(printf '%s' "$TESTARM_EXTS" | tr '|' ' '); do
    case "$EXT_LINE" in *"*.$EXT"*) : ;; *) EXT_MISSING="$EXT_MISSING $EXT" ;; esac
  done
  if [ -n "$EXT_MISSING" ]; then
    fail_ "T-ext-set-pinned" "BL-198-EXT-SET is missing source extensions the BL-125 arm treats as source:$EXT_MISSING — the no-signal branch fails OPEN for them"
  else
    BL198_WHY="$(_bl198_skip_reason)"
    if [ -n "$BL198_WHY" ]; then
      skip_ "T-ext-set-pinned" "static pin PASSED; behavioral half unprovable: $BL198_WHY"
    else
      # Both-parities NULs: 'A\0\0B' repeated — zeros at even AND odd offsets.
      awk 'BEGIN { for (i = 0; i < 64; i++) printf "A%c%cB", 0, 0 }' > "$BL198FIX/nosignal.bin"
      NS_NULS="$(_bl198_nuls "$BL198FIX/nosignal.bin")"
      NS_HEAD="$(_bl198_head4 "$BL198FIX/nosignal.bin" | cut -c1-4)"
      if [ "$NS_NULS" -eq 0 ] || [ "$NS_HEAD" = "fffe" ] || [ "$NS_HEAD" = "feff" ]; then
        fail_ "T-ext-set-pinned" "no-signal fixture malformed (nuls=$NS_NULS head=$NS_HEAD)"
      else
        NS_V="$(_bl198_run "$EMITTED" "$TOPTMP/bl198-nosignal" widget.ts "$BL198FIX/nosignal.bin")"
        if [ "$NS_V" = "COMMITTED" ] && grep -qF 'SAST NOT ENFORCED' "$TOPTMP/bl198-nosignal" \
           && grep -qF 'widget.ts' "$TOPTMP/bl198-nosignal" \
           && ! grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/bl198-nosignal"; then
          pass "T-ext-set-pinned: the test-arm source set is a subset of BL-198-EXT-SET (static), and an undecodable no-signal .ts routes LOUD and named, never receipted (behavioral) — binary-in-source-clothing is CAUGHT"
        else
          fail_ "T-ext-set-pinned" "verdict=$NS_V — a NUL-bearing no-signal .ts must be a loud named NOTRUN: $(sast_evidence "$TOPTMP/bl198-nosignal")"
        fi
      fi
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# BL-185 + BL-187 (Karl's 2026-07-31 decisions, recorded on their entries)
# ═══════════════════════════════════════════════════════════════════════════
# BL-185 "allow it, but log it": a staged `nosemgrep` directive must forfeit
# the UNQUALIFIED [OK] receipt, print a receipt NAMING file and directive, and
# append a `sast_suppression` row to .claude/bypass-audit.json — while the
# commit still LANDS (blocking was explicitly not chosen). BL-187: the
# per-rule budget is POLICY now — `--timeout=30` on the shipped invocation —
# and the old skip-shaped timeout proofs are re-armed via a BUDGET-SHRUNK
# mutant (30→1s) so the detector clause is provable on EVERY host instead of
# only hosts slow enough to blow a 30s budget.

# _mut_env <src> <dst> <old> <new> <want>: literal replace via ENVIRON — the
# suite's older _mut_n passes literals through `awk -v`, which PROCESSES
# ESCAPES; the `--timeout=30 \` literal ends in a lone backslash, the exact
# BSD-vs-mawk/gawk divergence that broke a CI shard on PR #293. ENVIRON
# passes bytes untouched everywhere. Numeric `want` stays -v (safe).
_mut_env() {
  SOIF_ME_OLD="$3" SOIF_ME_NEW="$4" awk -v want="$5" '
    { out = ""; rest = $0
      while ((p = index(rest, ENVIRON["SOIF_ME_OLD"])) > 0) {
        out = out substr(rest, 1, p-1) ENVIRON["SOIF_ME_NEW"]
        rest = substr(rest, p + length(ENVIRON["SOIF_ME_OLD"]))
        c++
      }
      print out rest }
    END { if (c != want) exit 3 }
  ' "$1" > "$2"
}

# ── T-bl187-constant: the shipped budget is 30, exactly once, as a real flag ──
echo "=== T-bl187-constant ==="
TB_N=$(grep -c -- '--timeout=30 \\' "$EMITTED") || TB_N=0
if [ "$TB_N" -eq 1 ]; then
  pass "T-bl187-constant (the emitted invocation carries --timeout=30 exactly once — the decided budget, not semgrep's 5s default)"
else
  fail_ "T-bl187-constant" "found $TB_N occurrences of '--timeout=30 \\' in the emitted hook (want exactly 1) — the 2026-07-31 decision sets the per-rule budget to 30s ON the shipped invocation; absent means the 5s default silently returned, duplicated means the invocation was mangled"
fi

# ── T-bl187-budget-mutant-proof: the timeout detector, provable on EVERY host ─
# The dense fixture's killing rule needs >5s but well under 30s on measured
# hosts, so at the shipped budget the sink is BLOCKED outright (strictly better)
# and the old timeout cases skip as UNPROVEN. This case re-arms the proof:
# shrink ONLY the budget constant (30 -> 1) in a copy of the shipped hook and
# the same fixture must FORFEIT with the timeout warn — the detector clause
# exercised for real, every host, cheaply (a 1s budget is FASTER than today).
# The intact control accepts the honest host disjunction: BLOCKED (rule fits
# the budget — the decision's intent) or forfeit-with-warn (a slow host blows
# even 30s); anything else fails.
echo "=== T-bl187-budget-mutant-proof ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-bl187-budget-mutant-proof" "semgrep ABSENT — UNPROVEN here (skip, NOT a pass)"
else
  MB="$TOPTMP/mut-budget-1s"
  if ! _mut_env "$EMITTED" "$MB" '--timeout=30 \' '--timeout=1 \' 1; then
    fail_ "T-bl187-budget-mutant-proof" "MIS-TARGETED — '--timeout=30 \\' not present exactly once in the emitted hook; retarget in lockstep with T-bl187-constant"
  elif ! bash -n "$MB" 2>/dev/null; then
    fail_ "T-bl187-budget-mutant-proof" "mutated hook has a syntax error — a broken mutant proves nothing"
  else
    chmod +x "$MB"
    MBD="$(mktemp -d)"
    if ! mk_repo "$MBD" "$MB" >/dev/null 2>&1; then
      fail_ "T-bl187-budget-mutant-proof" "fixture setup failed"
    else
      write_oversize_dense "$MBD/dense.ts" "$XSS_TS"
      if ! is_oversize "$MBD/dense.ts"; then
        skip_ "T-bl187-budget-mutant-proof" "dense fixture did not clear the oversize threshold on this host — UNPROVEN (skip, not pass)"
      else
        ( cd "$MBD" && git add -- dense.ts ) >/dev/null 2>&1
        if ( cd "$MBD" && git commit -m "feat: dense renderer" ) >"$TOPTMP/mb1.log" 2>&1; then MB_V=COMMITTED; else MB_V=REFUSED; fi
        if [ "$MB_V" = "REFUSED" ] && grep -qF '[BLOCKED] Semgrep' "$TOPTMP/mb1.log"; then
          skip_ "T-bl187-budget-mutant-proof" "this host finished the killing rule inside ONE second — nothing can time out here; the detector stays pinned only on slower hosts (skip, not pass)"
        elif [ "$MB_V" = "COMMITTED" ] && ! grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/mb1.log" \
             && grep -qF 'ABANDONED at least one rule' "$TOPTMP/mb1.log" \
             && grep -qF 'dense.ts' "$TOPTMP/mb1.log"; then
          # SECOND HALF — the conjunct-drop proof T-mutation-rule-timeout used to
          # carry, re-armed under the 1s budget (at the shipped 30s that case now
          # SKIPS on hosts whose rule fits the budget): drop ONLY the timeout
          # conjunct from the 1s-budget hook and the same dense sink must buy the
          # receipt back — the clause carries its own weight on EVERY host.
          MB2="$TOPTMP/mut-budget-1s-no-conjunct"
          if ! _mut_env "$MB" "$MB2" '&& [ "$soif_sg_timeouts" -eq 0 ]' '' 1; then
            fail_ "T-bl187-budget-mutant-proof" "MIS-TARGETED second half — the timeout conjunct is not present exactly once in the budget-mutant hook"
          elif ! bash -n "$MB2" 2>/dev/null; then
            fail_ "T-bl187-budget-mutant-proof" "second-half mutant has a syntax error — a broken mutant proves nothing"
          else
            chmod +x "$MB2"
            MBD2="$(mktemp -d)"
            if ! mk_repo "$MBD2" "$MB2" >/dev/null 2>&1; then
              fail_ "T-bl187-budget-mutant-proof" "second-half fixture setup failed"
            else
              write_oversize_dense "$MBD2/dense.ts" "$XSS_TS"
              ( cd "$MBD2" && git add -- dense.ts ) >/dev/null 2>&1
              ( cd "$MBD2" && git commit -m "feat: dense renderer" ) >"$TOPTMP/mb2.log" 2>&1 || true
              if grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/mb2.log"; then
                pass "T-bl187-budget-mutant-proof: 1s budget forfeits with the warn naming dense.ts (detector real); dropping the timeout conjunct under the same budget buys the receipt back (clause load-bearing) — both halves proven on THIS host"
              else
                fail_ "T-bl187-budget-mutant-proof" "conjunct-drop under the 1s budget did NOT restore the receipt — the clause proof is not isolating its clause: $(tail -6 "$TOPTMP/mb2.log" | tr '\n' '|')"
              fi
              rm -rf "$MBD2"
            fi
          fi
        else
          fail_ "T-bl187-budget-mutant-proof" "at a 1s budget expected COMMITTED + forfeited receipt + timeout warn naming dense.ts; got $MB_V: $(tail -8 "$TOPTMP/mb1.log" | tr '\n' '|')"
        fi
      fi
      rm -rf "$MBD"
    fi
  fi
fi

# ── T-bl185-suppression-receipt: the one unrecorded escape gets its logbook ──
# THREE SPELLINGS, one loop — review R-HP-1 proved semgrep honors `nosem`
# (the legacy short directive, --enable-nosem default per its own docs) and
# matches case-INSENSITIVELY (`// NOSEMGREP` measured suppressing on 1.157.0),
# so a case-sensitive nosemgrep-only detector left the escape unrecorded under
# two sanctioned spellings. Each spelling must forfeit, name, and row.
# The naming pin is EXACT-MAPPED per R-HP-3: `in: app.ts` (accumulator's
# leading space) AND a negative assert that no per-index temp segment leaks —
# the reviewer's sed-neutralized mutant survived the old basename substring.
echo "=== T-bl185-suppression-receipt ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-bl185-suppression-receipt" "semgrep ABSENT — UNPROVEN here (skip, NOT a pass)"
else
  SP_ALL=PASS
  for SP_DIR in '// nosemgrep' '// nosem' '// NOSEMGREP'; do
    SPD="$(mktemp -d)"
    if ! mk_repo "$SPD" "$EMITTED" >/dev/null 2>&1; then
      fail_ "T-bl185-suppression-receipt" "fixture setup failed ($SP_DIR)"; SP_ALL=FAIL; rm -rf "$SPD"; continue
    fi
    # Generated projects SHIP scripts/lib/bypass-audit.sh; the row half needs
    # it in the fixture, exactly as BL-163's row tests do.
    mkdir -p "$SPD/scripts/lib" "$SPD/.claude"
    cp "$REPO_ROOT/scripts/lib/bypass-audit.sh" "$SPD/scripts/lib/" 2>/dev/null || true
    printf 'export function render(pane, userText) {\n  %s\n  pane.innerHTML = userText;\n}\n' "$SP_DIR" > "$SPD/app.ts"
    ( cd "$SPD" && git add -- app.ts ) >/dev/null 2>&1
    if ( cd "$SPD" && git commit -m "feat: renderer with a suppression" ) >"$TOPTMP/sp1.log" 2>&1; then SP_V=COMMITTED; else SP_V=REFUSED; fi
    SP_ROW=0
    if command -v jq >/dev/null 2>&1 && [ -f "$SPD/.claude/bypass-audit.json" ]; then
      SP_ROW=$(jq '[.[] | select(.type == "sast_suppression")] | length' "$SPD/.claude/bypass-audit.json" 2>/dev/null) || SP_ROW=0
    fi
    SP_SINK=$( cd "$SPD" && git show HEAD:app.ts 2>/dev/null | grep -c innerHTML ) || SP_SINK=0
    if [ "$SP_V" != "COMMITTED" ]; then
      fail_ "T-bl185-suppression-receipt" "($SP_DIR) the suppressed commit was REFUSED — allow-but-log, never block: $(tail -6 "$TOPTMP/sp1.log" | tr '\n' '|')"; SP_ALL=FAIL
    elif [ "$SP_SINK" -lt 1 ]; then
      fail_ "T-bl185-suppression-receipt" "($SP_DIR) fixture defect — the sink did not land in HEAD; the case proves nothing"; SP_ALL=FAIL
    elif grep -qE 'no ERROR-severity findings\.$' "$TOPTMP/sp1.log"; then
      fail_ "T-bl185-suppression-receipt" "($SP_DIR) the UNQUALIFIED receipt printed over a suppressed sink — the exact false attestation BL-185 exists to end (semgrep honors this spelling; the detector must too): $(tail -6 "$TOPTMP/sp1.log" | tr '\n' '|')"; SP_ALL=FAIL
    elif ! grep -qF 'suppression' "$TOPTMP/sp1.log" || ! grep -qF 'in: app.ts' "$TOPTMP/sp1.log"; then
      fail_ "T-bl185-suppression-receipt" "($SP_DIR) the receipt does not NAME the suppression with the MAPPED path 'in: app.ts': $(tail -8 "$TOPTMP/sp1.log" | tr '\n' '|')"; SP_ALL=FAIL
    elif grep -qE 'in: .*/[0-9][0-9]*/app\.ts' "$TOPTMP/sp1.log"; then
      fail_ "T-bl185-suppression-receipt" "($SP_DIR) the receipt leaks the materialized per-index temp path — the mapping sed is broken (R-HP-3's mutant): $(tail -8 "$TOPTMP/sp1.log" | tr '\n' '|')"; SP_ALL=FAIL
    elif [ "${SP_ROW:-0}" -lt 1 ]; then
      fail_ "T-bl185-suppression-receipt" "($SP_DIR) no sast_suppression row (rows=$SP_ROW) — the logbook half: $(tail -6 "$TOPTMP/sp1.log" | tr '\n' '|')"; SP_ALL=FAIL
    fi
    rm -rf "$SPD"
  done
  if [ "$SP_ALL" = "PASS" ]; then
    pass "T-bl185-suppression-receipt: all three semgrep-honored spellings (nosemgrep / nosem / NOSEMGREP) forfeit the unqualified [OK], name 'in: app.ts' mapped, and write the row"
  fi
fi

# ── T-bl185-blocked-path: refused commit => info line, NO row (R-HP-5a) ─────
echo "=== T-bl185-blocked-path ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-bl185-blocked-path" "semgrep ABSENT — UNPROVEN here (skip, NOT a pass)"
else
  BPD="$(mktemp -d)"
  if ! mk_repo "$BPD" "$EMITTED" >/dev/null 2>&1; then
    fail_ "T-bl185-blocked-path" "fixture setup failed"
  else
    mkdir -p "$BPD/scripts/lib" "$BPD/.claude"
    cp "$REPO_ROOT/scripts/lib/bypass-audit.sh" "$BPD/scripts/lib/" 2>/dev/null || true
    printf '%s\n' "$XSS_TS" > "$BPD/vuln.ts"
    printf 'export function safe(p, t) {\n  // nosemgrep\n  p.textContent = t;\n}\n' > "$BPD/other.ts"
    ( cd "$BPD" && git add -- vuln.ts other.ts ) >/dev/null 2>&1
    if ( cd "$BPD" && git commit -m "feat: two files" ) >"$TOPTMP/bp185.log" 2>&1; then BP_V=COMMITTED; else BP_V=REFUSED; fi
    BP_ROW=0
    if command -v jq >/dev/null 2>&1 && [ -f "$BPD/.claude/bypass-audit.json" ]; then
      BP_ROW=$(jq '[.[] | select(.type == "sast_suppression")] | length' "$BPD/.claude/bypass-audit.json" 2>/dev/null) || BP_ROW=0
    fi
    if [ "$BP_V" = "REFUSED" ] && grep -qF '[BLOCKED] Semgrep' "$TOPTMP/bp185.log" \
       && grep -qF 'suppression' "$TOPTMP/bp185.log" && [ "${BP_ROW:-0}" -eq 0 ]; then
      pass "T-bl185-blocked-path: a blocked commit still SHOWS the suppression info line but writes NO row — the block itself is the BL-163 ledger's event"
    else
      fail_ "T-bl185-blocked-path" "want REFUSED + [BLOCKED] + info line + rows=0; got V=$BP_V rows=$BP_ROW: $(tail -8 "$TOPTMP/bp185.log" | tr '\n' '|')"
    fi
    rm -rf "$BPD"
  fi
fi

# ── T-bl185-trojan-ledger: a trojan append lib cannot change the outcome ────
echo "=== T-bl185-trojan-ledger ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-bl185-trojan-ledger" "semgrep ABSENT — UNPROVEN here (skip, NOT a pass)"
else
  TJD="$(mktemp -d)"
  if ! mk_repo "$TJD" "$EMITTED" >/dev/null 2>&1; then
    fail_ "T-bl185-trojan-ledger" "fixture setup failed"
  else
    mkdir -p "$TJD/scripts/lib" "$TJD/.claude"
    printf '#!/bin/sh\nexit 3\n' > "$TJD/scripts/lib/bypass-audit.sh"
    printf 'export function safe(p, t) {\n  // nosemgrep\n  p.textContent = t;\n}\n' > "$TJD/app.ts"
    ( cd "$TJD" && git add -- app.ts ) >/dev/null 2>&1
    if ( cd "$TJD" && git commit -m "feat: safe file with a suppression" ) >"$TOPTMP/tj185.log" 2>&1; then TJ_V=COMMITTED; else TJ_V=REFUSED; fi
    if [ "$TJ_V" = "COMMITTED" ] && grep -qF '[note] BL-185: ledger append failed' "$TOPTMP/tj185.log"; then
      pass "T-bl185-trojan-ledger: a trojan/broken append lib degrades to the loud [note] — subshell-confined, commit outcome untouched (the BL-163 T4b discipline)"
    else
      fail_ "T-bl185-trojan-ledger" "want COMMITTED + the loud append-failed note; got V=$TJ_V: $(tail -6 "$TOPTMP/tj185.log" | tr '\n' '|')"
    fi
    rm -rf "$TJD"
  fi
fi

# ── T-bl185-clean-control: no suppression => byte-identical today-behavior ──
echo "=== T-bl185-clean-control ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-bl185-clean-control" "semgrep ABSENT — UNPROVEN here (skip, NOT a pass)"
else
  SCD="$(mktemp -d)"
  if ! mk_repo "$SCD" "$EMITTED" >/dev/null 2>&1; then
    fail_ "T-bl185-clean-control" "fixture setup failed"
  else
    # The append lib is PRESENT here too — otherwise "no audit row" would pass
    # vacuously on a fixture that cannot write rows at all. The file also
    # carries word-boundary NEIGHBORS of the directives (nosemantic,
    # xnosemgrepx) — semgrep ignores them and so must the detector (R-HP-1's
    # boundary pins).
    mkdir -p "$SCD/scripts/lib" "$SCD/.claude"
    cp "$REPO_ROOT/scripts/lib/bypass-audit.sh" "$SCD/scripts/lib/" 2>/dev/null || true
    printf '%s\n// the nosemantic xnosemgrepx neighbors must not trip the detector\n' "$SAFE_TS" > "$SCD/app.ts"
    ( cd "$SCD" && git add -- app.ts ) >/dev/null 2>&1
    if ( cd "$SCD" && git commit -m "feat: clean renderer" ) >"$TOPTMP/sc1.log" 2>&1; then SC_V=COMMITTED; else SC_V=REFUSED; fi
    SC_ROW=0
    if command -v jq >/dev/null 2>&1 && [ -f "$SCD/.claude/bypass-audit.json" ]; then
      SC_ROW=$(jq '[.[] | select(.type == "sast_suppression")] | length' "$SCD/.claude/bypass-audit.json" 2>/dev/null) || SC_ROW=0
    fi
    if [ "$SC_V" = "COMMITTED" ] && grep -qF '[OK] semgrep: SAST ran on 1 staged file(s) — no ERROR-severity findings.' "$TOPTMP/sc1.log" \
       && ! grep -qF 'BL-185:' "$TOPTMP/sc1.log" && [ "${SC_ROW:-0}" -eq 0 ]; then
      pass "T-bl185-clean-control: no directive => the exact unqualified receipt, no BL-185 line, no audit row — the detector does not cry wolf"
    else
      fail_ "T-bl185-clean-control" "clean commit disturbed (V=$SC_V rows=$SC_ROW): $(tail -6 "$TOPTMP/sc1.log" | tr '\n' '|')"
    fi
    rm -rf "$SCD"
  fi
fi

# ── T-bl185-mutation: the detect fence carries its own weight ────────────────
echo "=== T-bl185-mutation ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-bl185-mutation" "semgrep ABSENT — mutation UNPROVEN here (skip, NOT a pass)"
else
  MSP="$TOPTMP/mut-no-suppression-detect"
  MSP_B=$(grep -c '# BL-185-SUPPRESSION-DETECT-BEGIN' "$EMITTED") || MSP_B=0
  MSP_E=$(grep -c '# BL-185-SUPPRESSION-DETECT-END' "$EMITTED") || MSP_E=0
  sed '/# BL-185-SUPPRESSION-DETECT-BEGIN/,/# BL-185-SUPPRESSION-DETECT-END/d' "$EMITTED" > "$MSP"
  if [ "$MSP_B" -ne 1 ] || [ "$MSP_E" -ne 1 ]; then
    fail_ "T-bl185-mutation" "MIS-TARGETED — detect fence not present exactly once (begin=$MSP_B end=$MSP_E)"
  elif ! bash -n "$MSP" 2>/dev/null; then
    fail_ "T-bl185-mutation" "mutated hook has a syntax error — a broken mutant proves nothing"
  else
    chmod +x "$MSP"
    MSD="$(mktemp -d)"
    if ! mk_repo "$MSD" "$MSP" >/dev/null 2>&1; then
      fail_ "T-bl185-mutation" "mutation fixture setup failed"
    else
      printf 'export function render(pane, userText) {\n  // nosemgrep\n  pane.innerHTML = userText;\n}\n' > "$MSD/app.ts"
      ( cd "$MSD" && git add -- app.ts ) >/dev/null 2>&1
      ( cd "$MSD" && git commit -m "feat: renderer with a suppression" ) >"$TOPTMP/ms1.log" 2>&1 || true
      if grep -qF 'no ERROR-severity findings."' "$TOPTMP/ms1.log" || grep -qE 'no ERROR-severity findings\.$' "$TOPTMP/ms1.log"; then
        pass "T-bl185-mutation: excising the detect fence brings the unrecorded escape back (RED — unqualified [OK] over the suppressed sink); the intact GREEN half is T-bl185-suppression-receipt"
      else
        fail_ "T-bl185-mutation" "excising the fence did NOT restore the unqualified receipt — this case is not isolating the fence: $(tail -6 "$TOPTMP/ms1.log" | tr '\n' '|')"
      fi
      rm -rf "$MSD"
    fi
  fi
fi

# ── T-bl185-doc-mention: PROSE naming the directive is not a suppression ────
# Walk 2026-08-02 (walkrepo-1785713402, ISSUE-018): committing a Markdown
# report whose sentences DISCUSS the directive produced a
# `type: "sast_suppression"` row naming that .md — the security-review ledger
# gained a false suppression event for a file that suppresses nothing, and
# every honest write-up about suppressions accretes another one. semgrep has
# no analyzer for Markdown/plain-text: a directive there cannot skip a line,
# so those file classes are out of the detector's scope. BOTH directions in
# ONE fixture: the .md must produce no row and must not be named, while the
# .ts staged in the SAME commit still forfeits the receipt and rows.
echo "=== T-bl185-doc-mention ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-bl185-doc-mention" "semgrep ABSENT — UNPROVEN here (skip, NOT a pass)"
else
  DMD="$(mktemp -d)"
  if ! mk_repo "$DMD" "$EMITTED" >/dev/null 2>&1; then
    fail_ "T-bl185-doc-mention" "fixture setup failed"
  else
    mkdir -p "$DMD/scripts/lib" "$DMD/.claude"
    cp "$REPO_ROOT/scripts/lib/bypass-audit.sh" "$DMD/scripts/lib/" 2>/dev/null || true
    cat > "$DMD/NOTES.md" <<'MD'
# Walk report
The pre-commit gate records every `nosemgrep` directive as an audited
observation. A `// nosem` comment suppresses the following line, so the
report has to name the directive it is reporting on.
MD
    printf 'export function render(pane, userText) {\n  // nosemgrep\n  pane.innerHTML = userText;\n}\n' > "$DMD/app.ts"
    ( cd "$DMD" && git add -- NOTES.md app.ts ) >/dev/null 2>&1
    if ( cd "$DMD" && git commit -m "docs: walk report plus renderer" ) >"$TOPTMP/dm185.log" 2>&1; then DM_V=COMMITTED; else DM_V=REFUSED; fi
    DM_ROW_FILES=""
    if command -v jq >/dev/null 2>&1 && [ -f "$DMD/.claude/bypass-audit.json" ]; then
      DM_ROW_FILES=$(jq -r '[.[] | select(.type == "sast_suppression") | .details.files] | join(",")' "$DMD/.claude/bypass-audit.json" 2>/dev/null) || DM_ROW_FILES=""
    fi
    if [ "$DM_V" != "COMMITTED" ]; then
      fail_ "T-bl185-doc-mention" "the commit was REFUSED — allow-but-log, never block: $(tail -6 "$TOPTMP/dm185.log" | tr '\n' '|')"
    elif printf '%s' "$DM_ROW_FILES" | grep -qF 'NOTES.md' || grep -E 'BL-185:.*NOTES\.md' "$TOPTMP/dm185.log" >/dev/null 2>&1; then
      fail_ "T-bl185-doc-mention" "a .md that only MENTIONS the directive was recorded as carrying a suppression (ledger files='$DM_ROW_FILES') — semgrep cannot suppress a line it never scans; documenting the framework must not manufacture bypass records"
    elif ! printf '%s' "$DM_ROW_FILES" | grep -qF 'app.ts'; then
      fail_ "T-bl185-doc-mention" "the REAL suppression in app.ts stopped being recorded (ledger files='$DM_ROW_FILES') — the scoping went too far: $(tail -8 "$TOPTMP/dm185.log" | tr '\n' '|')"
    elif ! grep -qF 'in: app.ts' "$TOPTMP/dm185.log"; then
      fail_ "T-bl185-doc-mention" "the receipt no longer NAMES the real suppression: $(tail -8 "$TOPTMP/dm185.log" | tr '\n' '|')"
    else
      pass "T-bl185-doc-mention: a staged .md naming the directive produces NO row and is not named; the .ts in the same commit still forfeits and rows"
    fi
    rm -rf "$DMD"
  fi
fi

# ── T-bl185-doc-scope-mutation: the doc-class skip carries its own weight ────
echo "=== T-bl185-doc-scope-mutation ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-bl185-doc-scope-mutation" "semgrep ABSENT — mutation UNPROVEN here (skip, NOT a pass)"
else
  DSM="$TOPTMP/mut-no-doc-scope"
  DSM_B=$(grep -c '# BL-185-SUPPRESSION-DOC-SCOPE-BEGIN' "$EMITTED") || DSM_B=0
  DSM_E=$(grep -c '# BL-185-SUPPRESSION-DOC-SCOPE-END' "$EMITTED") || DSM_E=0
  sed '/# BL-185-SUPPRESSION-DOC-SCOPE-BEGIN/,/# BL-185-SUPPRESSION-DOC-SCOPE-END/d' "$EMITTED" > "$DSM"
  if [ "$DSM_B" -ne 1 ] || [ "$DSM_E" -ne 1 ]; then
    fail_ "T-bl185-doc-scope-mutation" "MIS-TARGETED — the doc-scope fence is not present exactly once (begin=$DSM_B end=$DSM_E)"
  elif ! bash -n "$DSM" 2>/dev/null; then
    fail_ "T-bl185-doc-scope-mutation" "mutated hook has a syntax error — a broken mutant proves nothing"
  else
    chmod +x "$DSM"
    DSD="$(mktemp -d)"
    if ! mk_repo "$DSD" "$DSM" >/dev/null 2>&1; then
      fail_ "T-bl185-doc-scope-mutation" "mutation fixture setup failed"
    else
      mkdir -p "$DSD/scripts/lib" "$DSD/.claude"
      cp "$REPO_ROOT/scripts/lib/bypass-audit.sh" "$DSD/scripts/lib/" 2>/dev/null || true
      printf '# Report\nThe gate logs every nosemgrep directive it sees.\n' > "$DSD/NOTES.md"
      ( cd "$DSD" && git add -- NOTES.md ) >/dev/null 2>&1
      ( cd "$DSD" && git commit -m "docs: walk report" ) >"$TOPTMP/ds185.log" 2>&1 || true
      if grep -E 'BL-185:.*NOTES\.md' "$TOPTMP/ds185.log" >/dev/null 2>&1; then
        pass "T-bl185-doc-scope-mutation: excising the doc-class skip brings the false suppression row back (RED) — the skip, not chance, is what keeps prose out of the ledger"
      else
        fail_ "T-bl185-doc-scope-mutation" "excising the fence did NOT reproduce the ISSUE-018 row — this case is not isolating the skip: $(tail -8 "$TOPTMP/ds185.log" | tr '\n' '|')"
      fi
      rm -rf "$DSD"
    fi
  fi
fi

echo ""
if [ "$SKIPPED" -gt 0 ]; then echo "!! $SKIPPED case(s) SKIPPED — skipped != passed."; fi
echo "Results: $PASSED passed, $FAILED failed ($SKIPPED skipped)"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

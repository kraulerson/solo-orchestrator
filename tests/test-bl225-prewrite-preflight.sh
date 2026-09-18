#!/usr/bin/env bash
# tests/test-bl225-prewrite-preflight.sh
#
# `## BL-225:` — THE BEFORE-ANY-WRITE HALF.
#
# `# BL-225-STAGE-PREFLIGHT` protects the INDEX: it asks `git add --dry-run`
# before staging and stops whole. By the time it runs ~78 files are already on
# disk, and the entry says so in as many words: "The index is protected; the
# disk is not." This suite is the other half — a refusal that arrives before
# the FIRST write, so a project whose `.gitignore` refuses one of the files the
# adoption must write is left byte-identical instead of half-installed.
#
# THE DESIGN UNDER TEST. `_adopt_write_phase` is the only writer of the
# adoptee's files and is called twice: once by `adopt_prewrite_preflight`
# against a COPY of the tree, once for real. The planned path set is therefore
# not a maintained list that can drift behind the writers — it is what the
# writers produced on a rehearsal.
#
# WHAT IS STUBBED AND WHY. T1-T5 replace `_adopt_write_phase` with a stub that
# records a known path set. That is deliberate: these cases are about the
# DECISION (which oracle, what it refuses, what it leaves behind), and a real
# write phase needs a Scout report, a framework clone and an answered intake —
# fidelity the adoption e2e suites already cover. T6 closes the gap the stub
# opens, structurally: the preflight must be CALLED before the real phase.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/adopt"
STATE="$LIB/adopt-state.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  [PASS] $1"; }
bad() { FAIL=$((FAIL+1)); echo "  [FAIL] $1"; }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/bl225pw.XXXXXX")" || exit 1
case "$WORK" in "$REPO_ROOT"*) echo "FATAL: fixture inside repo"; exit 1 ;; esac
trap 'rm -rf "$WORK"' EXIT INT TERM
# A global excludes file carrying `.claude/` would make every adoptee look
# ignored; GIT_CONFIG_GLOBAL does not cover it, so neutralise the PATH default.
export XDG_CONFIG_HOME="$WORK/xdg"; mkdir -p "$XDG_CONFIG_HOME"
export HOME="$WORK/home"; mkdir -p "$HOME"

[ -f "$STATE" ] || { echo "  [FAIL] setup — $STATE not found"; echo ""; echo "Results: 0 passed, 1 failed"; exit 1; }

# _adoptee DIR [ignore-line...] — a real git repo with their own history
_adoptee() {
  local d="$1"; shift
  mkdir -p "$d" && ( cd "$d" \
    && git init -q -b main . \
    && git config user.email t@example.com && git config user.name T \
    && printf 'their code\n' > README.md \
    && { [ "$#" -eq 0 ] || printf '%s\n' "$@" > .gitignore; } \
    && git add -A && git commit -q -m 'chore: their history' ) || return 1
}
# _hash DIR — a content hash of the whole tree, .git included, so "unchanged"
# means unchanged rather than "no file I thought to check".
_hash() { ( cd "$1" && find . -type f -exec cksum {} \; 2>/dev/null | LC_ALL=C sort | cksum ); }

# _run DIR PLANNED... -> "rc|err" with _adopt_write_phase stubbed to record PLANNED
_run() {
  local d="$1"; shift
  ( set +e
    ADOPT_PROJECT_NAME=t
    . "$LIB/adopt-core.sh"  >/dev/null 2>&1
    . "$STATE"              >/dev/null 2>&1
    ADOPT_WORK="$WORK/w.$$"; mkdir -p "$ADOPT_WORK"
    adopt_ledger_init "$ADOPT_WORK/written" >/dev/null 2>&1
    REAL_LEDGER="$ADOPT_WRITTEN_LEDGER"
    _planned="$*"
    # The stub is the rehearsal's write phase: it records into whatever ledger
    # the preflight pointed it at, exactly as the real writers do.
    _adopt_write_phase() {
      local p
      for p in $_planned; do adopt_record_write "$p"; done
      return 0
    }
    err=$(adopt_prewrite_preflight "$d" "" 2>&1 >/dev/null); rc=$?
    printf '%s|%s|%s|%s\n' "$rc" "$(printf '%s' "$err" | tr '\n' ' ')" \
      "$([ "$ADOPT_WRITTEN_LEDGER" = "$REAL_LEDGER" ] && echo restored || echo LOST)" \
      "$([ -e "$ADOPT_WORK/rehearsal" ] && echo residue || echo clean)" )
}

# _run_marked DIR MARKS PLANNED... -> "rc|err" — same as _run, but raises the
# touched-disk markers BEFORE the preflight, exactly as the arms that raise
# them do.
#
# THIS CASE EXISTS BECAUSE E4/E5 CANNOT CARRY IT. E4/E5 reach the derived arm
# only when the tool resolver raises the marker, and the resolver returns
# early — before `adopt_touched_disk` — when gitleaks is already installed.
# The PR-blocking `unit-shard` job installs gitleaks unconditionally and this
# Mac has it on PATH, so on every host that actually gates a merge E4/E5 pass
# whether or not the derived arm exists at all: measured, deleting the whole
# arm left the suite at 26/0 on macOS and 26/0 on a container WITH gitleaks,
# and went red only on a bare container without it. A guard that the gating
# hosts cannot fail is not a guard. These cases raise the markers themselves,
# so they discriminate on any host and with any tool inventory.
# MARKS is a comma list: `touched`, `unbounded`, or both.
_run_marked() {
  local d="$1" marks="$2"; shift 2
  ( set +e
    ADOPT_PROJECT_NAME=t
    . "$LIB/adopt-core.sh"  >/dev/null 2>&1
    . "$STATE"              >/dev/null 2>&1
    ADOPT_WORK="$WORK/wm.$$.$RANDOM"; mkdir -p "$ADOPT_WORK"
    adopt_ledger_init "$ADOPT_WORK/written" >/dev/null 2>&1
    case ",$marks," in *,touched,*)   adopt_touched_disk ;; esac
    case ",$marks," in *,unbounded,*) adopt_touched_disk_unbounded ;; esac
    _planned="$*"
    _adopt_write_phase() {
      local p
      for p in $_planned; do adopt_record_write "$p"; done
      return 0
    }
    err=$(adopt_prewrite_preflight "$d" "" 2>&1 >/dev/null); rc=$?
    printf '%s|%s\n' "$rc" "$(printf '%s' "$err" | tr '\n' ' ')" )
}

echo "=== T — the refusal arrives before the first write ==="

# T1 — THE DISCRIMINATOR. Their .gitignore hides .claude/, which is where the
# adoption's own state lives. Today ~78 files land before anything notices.
P1="$WORK/t1"; _adoptee "$P1" '.claude/'
H1="$(_hash "$P1")"
IFS='|' read -r rc1 err1 led1 res1 <<<"$(_run "$P1" '.claude/manifest.json' 'PROJECT_INTAKE.md')"
chk "T1: refuses (rc != 0)"                         "$([ "${rc1:-0}" -ne 0 ] && echo yes || echo no)" "yes"
chk "T1: names the refused path"                    "$(printf '%s' "$err1" | grep -c 'manifest.json')" "1"
chk "T1: says nothing was written"                  "$(printf '%s' "$err1" | grep -ci 'NOTHING WAS WRITTEN')" "1"
chk "T1: and the project is BYTE-IDENTICAL"         "$(_hash "$P1")" "$H1"

# T2 — the control: a project with no rule in the way is allowed through, and
# the rehearsal still leaves it untouched.
P2="$WORK/t2"; _adoptee "$P2"
H2="$(_hash "$P2")"
IFS='|' read -r rc2 err2 led2 res2 <<<"$(_run "$P2" '.claude/manifest.json' 'PROJECT_INTAKE.md')"
chk "T2: allows a project with no rule in the way"  "${rc2:-x}" "0"
chk "T2: and left it BYTE-IDENTICAL too"            "$(_hash "$P2")" "$H2"

# T3 — the rehearsal copy is removed. A copy of someone's whole repository
# left behind under /tmp is a disclosure of their code, not just litter.
chk "T3: the rehearsal copy is deleted (refused run)" "${res1:-x}" "clean"
chk "T3: the rehearsal copy is deleted (allowed run)" "${res2:-x}" "clean"

# T4 — the ledger is global. If the rehearsal's ledger leaked into the real run,
# the commit would stage files the real run never wrote.
chk "T4: the real ledger is restored (refused run)" "${led1:-x}" "restored"
chk "T4: the real ledger is restored (allowed run)" "${led2:-x}" "restored"

# T5 — NEGATION, both halves, because git treats them differently and a first
# draft of this case asserted the wrong one. gitignore(5): "It is not possible
# to re-include a file if a parent directory of that file is excluded." So:
#   a) '.claude/' + '!.claude/manifest.json'  -> STILL ignored. Refusing is
#      correct, and matches what `git add` would do.
#   b) '*.json'   + '!manifest.json'          -> re-included. Allowing is
#      correct, and a naive "is any parent ignored" test would get this wrong.
P5a="$WORK/t5a"; _adoptee "$P5a" '.claude/' '!.claude/manifest.json'
IFS='|' read -r rc5a _ _ _ <<<"$(_run "$P5a" '.claude/manifest.json')"
chk "T5a: '!' under an ignored DIRECTORY does not re-include — still refused" \
  "$([ "${rc5a:-0}" -ne 0 ] && echo yes || echo no)" "yes"
P5b="$WORK/t5b"; _adoptee "$P5b" '*.json' '!manifest.json'
IFS='|' read -r rc5b _ _ _ <<<"$(_run "$P5b" 'manifest.json')"
chk "T5b: a genuinely re-included path is allowed (negation is honoured)" "${rc5b:-x}" "0"

# T8 — THE DERIVED CLEAR, ON ANY HOST. Three states of the two markers.
#
# T8a: the coarse marker is raised, no planned path landed, the unbounded
# writer never ran -> the marker was pessimistic and the refusal must say so.
P8a="$WORK/t8a"; _adoptee "$P8a" '.claude/'
IFS='|' read -r rc8a err8a <<<"$(_run_marked "$P8a" 'touched' '.claude/manifest.json' 'PROJECT_INTAKE.md')"
chk "T8a: still refuses"                            "$([ "${rc8a:-0}" -ne 0 ] && echo yes || echo no)" "yes"
# RE-AIMED BY WP9d (§10-WP9d item 5) — see E4 below for the full reasoning.
# The label follows docs/messaging-standard.md (a check RAN); the honest
# sentence moved to the detail, and both halves are pinned here.
chk "T8a: labelled BLOCKED — a check ran (WP9d re-aim)" "$(printf '%s' "$err8a" | grep -c 'BLOCKED')" "1"
chk "T8a: and still says nothing was written"       "$(printf '%s' "$err8a" | grep -c 'nothing was written')" "1"
chk "T8a: and does NOT claim it ATTEMPTED writes"   "$(printf '%s' "$err8a" | grep -ci 'ATTEMPTED writes')" "0"

# T8b: the UNBOUNDED writer ran. The planned set does not bound what an eval'd
# install recipe writes, so the marker must survive the derivation. This is the
# case that goes red if the clear is a replacement instead of an intersection.
P8b="$WORK/t8b"; _adoptee "$P8b" '.claude/'
IFS='|' read -r rc8b err8b <<<"$(_run_marked "$P8b" 'touched,unbounded' '.claude/manifest.json' 'PROJECT_INTAKE.md')"
chk "T8b: refuses"                                  "$([ "${rc8b:-0}" -ne 0 ] && echo yes || echo no)" "yes"
chk "T8b: an unbounded writer keeps the pessimistic message" \
  "$(printf '%s' "$err8b" | grep -ci 'ATTEMPTED writes')" "1"

# T8c: a planned path EXISTS in the tree. Whether this adoption put it there or
# the operator already had it, the derivation cannot tell — so it keeps the
# marker. Conservative by design.
P8c="$WORK/t8c"; _adoptee "$P8c" '.claude/'
printf 'theirs\n' > "$P8c/PROJECT_INTAKE.md"
IFS='|' read -r rc8c err8c <<<"$(_run_marked "$P8c" 'touched' '.claude/manifest.json' 'PROJECT_INTAKE.md')"
chk "T8c: a landed planned path keeps the pessimistic message" \
  "$(printf '%s' "$err8c" | grep -ci 'ATTEMPTED writes')" "1"

# T9 — THE UNBOUNDED FLAG IS EVIDENCE, NOT AN ATTEMPT. The resolver cannot know
# what an eval'd recipe writes, so it fingerprints the adoptee's path list
# either side of the eval. The distinction is load-bearing in both directions:
# an attempt-based flag re-opens the over-claim on a host whose recipe ran and
# changed nothing (the bare-container case that failed E4/E5), and no flag at
# all lets the refusal say "nothing was written" over a leftover file.
T9D="$WORK/t9fp"; _adoptee "$T9D"
(
  . "$LIB/adopt-core.sh" >/dev/null 2>&1
  fp0="$(adopt_tree_fingerprint "$T9D")";           printf 'fp0=%s\n' "$fp0"
  fp1="$(adopt_tree_fingerprint "$T9D")";           printf 'fp1=%s\n' "$fp1"
  printf 'leftover\n' > "$T9D/installer-left-this.txt"
  fp2="$(adopt_tree_fingerprint "$T9D")";           printf 'fp2=%s\n' "$fp2"
  adopt_tree_fingerprint "$WORK/no-such-dir" >/dev/null 2>&1; printf 'rc_missing=%s\n' "$?"
) > "$WORK/t9.out" 2>&1
_t9() { grep "^$1=" "$WORK/t9.out" | head -1 | cut -d= -f2-; }
chk "T9a: the fingerprint is stable across two reads of an unchanged tree" \
  "$([ -n "$(_t9 fp0)" ] && [ "$(_t9 fp0)" = "$(_t9 fp1)" ] && echo yes || echo no)" "yes"
chk "T9b: and CHANGES when a recipe leaves a file behind" \
  "$([ "$(_t9 fp0)" != "$(_t9 fp2)" ] && echo yes || echo no)" "yes"
chk "T9c: a MISSING tree returns non-zero — callers must read that as 'assume it changed'" \
  "$([ "$(_t9 rc_missing)" != "0" ] && echo yes || echo no)" "yes"

# T9e — FAIL-CLOSED WITHOUT BORROWING IT FROM THE CALLER. A first cut piped
# `find` straight into `cksum`, so on a tree with an unreadable subdirectory it
# printed a PARTIAL fingerprint and returned 0 unless the caller happened to
# have `pipefail` on — measured, `OLD rc=0 out=[2705595490 24]` with pipefail
# off against `NEW rc=1 out=[]`. A truncated path list that compares equal on
# both sides is a silent all-clear, and the guarantee must not depend on a
# shell option set three files away. Root can read anything, so the case
# states that rather than passing vacuously.
T9E="$WORK/t9unreadable"; mkdir -p "$T9E/good" "$T9E/bad"
printf 'a\n' > "$T9E/good/a"; printf 'b\n' > "$T9E/bad/b"; chmod 300 "$T9E/bad"
if find "$T9E" -print >/dev/null 2>&1; then
  ok "T9e: SKIPPED — this user can read a chmod 300 directory (root?), so the case cannot discriminate"
else
  _t9e="$( set +o pipefail
    . "$LIB/adopt-core.sh" >/dev/null 2>&1
    out="$(adopt_tree_fingerprint "$T9E")"; printf '%s|%s' "$?" "$out" )"
  chk "T9e: an UNREADABLE tree returns non-zero even with pipefail OFF" \
    "$([ "${_t9e%%|*}" != "0" ] && echo yes || echo no)" "yes"
  chk "T9e: and prints nothing — a partial fingerprint would compare equal and read as clean" \
    "${_t9e#*|}" ""
fi
chmod 700 "$T9E/bad" 2>/dev/null || true

# T9d — the resolver's gate, structurally: the fingerprint is taken BEFORE the
# eval and compared AFTER it, and the flag is raised from the comparison rather
# than unconditionally. A one-line drift back to an unconditional raise is the
# regression this pins.
TOOLS="$LIB/adopt-tools.sh"
chk "T9d: the resolver raises the unbounded flag exactly once" \
  "$(grep -c 'adopt_touched_disk_unbounded   # BL-225-TOUCHED-UNBOUNDED' "$TOOLS")" "1"
chk "T9d: and it is guarded by a fingerprint comparison, not unconditional" \
  "$(grep -c '_bl225_fp_before" != "\$_bl225_fp_after' "$TOOLS")" "1"
chk "T9d: the BEFORE fingerprint precedes the eval" \
  "$([ "$(grep -n '_bl225_fp_before=' "$TOOLS" | head -1 | cut -d: -f1)" \
     -lt "$(grep -n 'BL-242-RESOLVER-INSTALL' "$TOOLS" | head -1 | cut -d: -f1)" ] && echo yes || echo no)" "yes"

# T10 — THE RESOLVER'S OWN GATE, BEHAVIOURALLY, ON ANY HOST.
#
# T9d is three greps, and a grep cannot see a one-token drift that keeps the
# shape and loses the meaning: renaming the variable that supplies the tree
# leaves both fingerprints empty, which fails closed, which raises the flag
# ALWAYS, which puts "ATTEMPTED writes" back on every clean tree — and that
# mutant passed all 38 checks and all 16 lints. Neither CI lane can catch it
# either: `E4`/`E5` are the only cases that reach the eval and they reach it
# only when gitleaks is ABSENT, while `unit-shard` and `full` both install it
# unconditionally. So this case drives `adopt_resolve_tools` itself with a
# stubbed matrix — no gitleaks, no network, no container — and reads the flag.
_run_resolver() {
  local root="$1" recipe="$2"
  ( set +e
    ADOPT_PROJECT_NAME=t
    . "$LIB/adopt-core.sh"  >/dev/null 2>&1
    . "$LIB/adopt-tools.sh" >/dev/null 2>&1
    ADOPT_WORK="$WORK/wr.$$.$RANDOM"; mkdir -p "$ADOPT_WORK"
    ADOPT_FRAMEWORK_ROOT="$ADOPT_WORK/fw"; mkdir -p "$ADOPT_FRAMEWORK_ROOT"
    # A resolver that always offers gitleaks in the auto bucket, carrying the
    # recipe this case wants evaluated.
    RES="$ADOPT_WORK/resolver.sh"
    {
      printf '#!/usr/bin/env bash\n'
      printf 'cat <<JSON\n'
      printf '{"already_installed":[],"manual_install":[],"auto_install":[{"name":"gitleaks","category":"Secret Detection","install_cmd":"%s"}]}\n' "$recipe"
      printf 'JSON\n'
    } > "$RES" && chmod +x "$RES"
    _adopt_resolver_path()  { printf '%s' "$RES"; }
    _adopt_scanner_present() { return 1; }
    _adopt_tools_language()  { printf 'shell'; }
    _adopt_tools_devos()     { printf 'macos'; }
    _adopt_cmd_is_runnable() { return 0; }
    _adopt_rescan_secrets()  { return 0; }
    adopt_ask_choice()       { ADOPT_ANSWER="set it up now"; return 0; }
    adopt_resolve_tools "$root" "" >/dev/null 2>&1
    printf '%s|%s|%s\n' \
      "$(adopt_has_touched_disk    && echo raised || echo unraised)" \
      "$(adopt_has_unbounded_write && echo raised || echo unraised)" \
      "$ADOPT_WORK" )
}

TA="$WORK/t10a"; _adoptee "$TA"
IFS='|' read -r t10a_c t10a_u _ <<<"$(_run_resolver "$TA" 'true')"
chk "T10a: a recipe that ran and changed nothing raises the COARSE marker" "${t10a_c:-x}" "raised"
chk "T10a: and does NOT raise the unbounded flag — the tree is provably unchanged" \
  "${t10a_u:-x}" "unraised"

TB="$WORK/t10b"; _adoptee "$TB"
IFS='|' read -r t10b_c t10b_u _ <<<"$(_run_resolver "$TB" "printf x > '$TB/installer-escaped.txt'")"
chk "T10b: a recipe that writes INTO the adoptee raises the unbounded flag" \
  "${t10b_u:-x}" "raised"
chk "T10b: and the file really is there, so the flag is evidence and not a guess" \
  "$([ -f "$TB/installer-escaped.txt" ] && echo yes || echo no)" "yes"

# T10c — the fingerprint reads THE ADOPTEE. A drift to any other tree (an
# unset global, the work dir, the cwd) leaves both sides equal or both empty,
# and T10b is what notices. This case pins the other direction: a recipe that
# writes into the WORK dir, where the eval already runs, must NOT raise it.
TC="$WORK/t10c"; _adoptee "$TC"
IFS='|' read -r t10c_c t10c_u t10c_w <<<"$(_run_resolver "$TC" 'printf x > ./relative-write.txt')"
# REACH GUARD AND RECEIPT, because T10c is the SOLE killer of the highest-value
# mutant in this file — the eval's `cd` drifting back to the adoptee, which is
# the original measured BL-242/BL-225 escape. A bare negative assertion is
# green when the recipe never ran at all, and the stub's hand-built JSON is one
# quote character away from that: a recipe containing `"` or `\` empties
# `name` and `adopt_resolve_tools` returns before the eval. So assert the arm
# was reached AND that the write actually landed where this case says it does.
chk "T10c: the run reached the eval arm (coarse marker raised)" "${t10c_c:-x}" "raised"
chk "T10c: and the relative write really landed in the work dir" \
  "$([ -f "${t10c_w:-/nonexistent}/relative-write.txt" ] && echo yes || echo no)" "yes"
chk "T10c: so a relative write misses the adoptee — flag stays down" \
  "${t10c_u:-x}" "unraised"

# T10d — THE FAIL-CLOSED ARM, which nothing tested. `adopt_tree_fingerprint`
# returning rc 1 with empty stdout is only worth something because the resolver
# turns it into a RAISE. Deleting that `-z` half — or making the `||` sentinel
# non-empty so `-z` can never fire — left the suite at 45/0 and the lints at
# 16/0, while an installer's real leftover file sat in the tree under "nothing
# was written". An unreadable subdirectory is the reachable trigger: `find`
# exits non-zero, the fingerprint refuses to answer, and the refusal must take
# the pessimistic branch rather than compare two empty strings and call them
# equal. Root can read anything, so the case says so rather than passing
# vacuously.
TD="$WORK/t10d"; _adoptee "$TD"; mkdir -p "$TD/unreadable"
printf 'x\n' > "$TD/unreadable/x"; chmod 300 "$TD/unreadable"
if find "$TD" -print >/dev/null 2>&1; then
  ok "T10d: SKIPPED — this user can read a chmod 300 directory (root?), so the case cannot discriminate"
else
  IFS='|' read -r t10d_c t10d_u _ <<<"$(_run_resolver "$TD" "printf x > '$TD/installer-escaped.txt'")"
  chk "T10d: the run reached the eval arm (coarse marker raised)" "${t10d_c:-x}" "raised"
  chk "T10d: an UNANSWERABLE fingerprint raises the flag — it does not read as unchanged" \
    "${t10d_u:-x}" "raised"
  chk "T10d: and the installer's file really is there, so the pessimism is earned" \
    "$([ -f "$TD/installer-escaped.txt" ] && echo yes || echo no)" "yes"
fi
chmod 700 "$TD/unreadable" 2>/dev/null || true

echo "=== E — the REAL driver, un-stubbed ==="

# T1-T5 stub `_adopt_write_phase`, and that stub is a hole the review found:
# a rehearsal pointed at "$root" instead of "$copy" — the original defect with a
# lie on top — passed all 20 cases, because a stub that writes nowhere cannot
# make a byte-identical assertion fail. So run the REAL driver once. This case
# is the one that kills:
#   - pointing the rehearsal at the project instead of the copy
#   - moving `adopt_test_debt_record` back above the preflight (a file lands,
#     and the refusal's "nothing was written" becomes false)
#   - dropping `# BL-225-REHEARSAL-NO-TRACE` (the tree stays clean but the
#     refusal claims adoption ATTEMPTED writes to the project)
# It needs a Scout report, so it SKIPS LOUDLY rather than silently if scout
# cannot produce one — a skipped case that reads as a pass is how the stub hole
# stayed open.
E_ROOT="$WORK/e2e"; E_P="$E_ROOT/p"; mkdir -p "$E_ROOT"
mkdir -p "$E_P/src" && ( cd "$E_P" && git init -q . \
  && git config user.email e@test.invalid && git config user.name E \
  && printf '{"name":"acme","scripts":{"test":"npm test"}}\n' > package.json \
  && printf '# acme\n' > README.md \
  && printf '.claude/\n' > .gitignore \
  && git add -A && git commit -q -m 'chore: their history' ) >/dev/null 2>&1
if ! bash "$REPO_ROOT/scripts/scout.sh" --root "$E_P" --out "$E_ROOT/scan" >/dev/null 2>&1 \
   || [ ! -s "$E_ROOT/scan/scout-report.json" ]; then
  bad "E setup — scripts/scout.sh produced no report; the end-to-end case cannot run, and is NOT silently skipped"
else
  E_HASH_BEFORE="$(_hash "$E_P")"
  # ENOUGH ANSWERS TO REACH THE PREFLIGHT, AND A LOUD FAILURE IF WE DO NOT.
  # A fixed 5-line stream underran the intake on a host without node/npm: the
  # driver stopped at "Tooling Configuration ... no answer was given" BEFORE the
  # preflight, so E1-E3 passed VACUOUSLY (nothing ran, so nothing was written)
  # and E4/E5 read the intake abort's message instead of the preflight's.
  # Measured in `ubuntu:24.04`: 23/2 there against 25/0 on this Mac, for a
  # fixture difference and not a product difference. E0 below is the guard: if
  # the run did not reach the preflight, say so instead of asserting anything.
  { printf '2\n'; i=0; while [ "$i" -lt 40 ]; do printf '1\n'; i=$((i + 1)); done; } > "$E_ROOT/answers"
  E_ERR="$E_ROOT/err"
  ( cd "$E_P" && bash "$REPO_ROOT/scripts/adopt-project.sh" \
      --scan-report "$E_ROOT/scan/scout-report.json" ) < "$E_ROOT/answers" >/dev/null 2>"$E_ERR"
  E_RC=$?
  E_DIRTY="$( cd "$E_P" && git status --porcelain --ignored --untracked-files=all 2>/dev/null | grep -c . )"
  # E0 — the run must have reached the PREFLIGHT. Without this every assertion
  # below is satisfied by a driver that stopped earlier for an unrelated reason.
  chk "E0 — the run reached the pre-write preflight (not an earlier abort)" \
    "$(grep -c 'your ignore rules refuse' "$E_ERR")" "1"
  chk "E1 — the real driver REFUSES an adoptee whose rules hide .claude/" \
    "$([ "$E_RC" -ne 0 ] && echo yes || echo no)" "yes"
  chk "E2 — and the project is BYTE-IDENTICAL afterwards (real writers, no stub)" \
    "$(_hash "$E_P")" "$E_HASH_BEFORE"
  chk "E3 — not one file, tracked, untracked or ignored, was left behind" "$E_DIRTY" "0"
  # RE-AIMED BY WP9d (ADOPT-002-ARCH v2.2 §10-WP9d item 5). This pinned the
  # LABEL because, at the time, the label was the only thing carrying "nothing
  # was written" — `adopt_refuse` derived it from the disk.
  # `docs/messaging-standard.md` draws the line elsewhere: a REFUSAL is "the
  # tool would not begin", a BLOCK is "a check ran and you did not pass it".
  # The pre-write rehearsal is a check that RAN. The label follows the standard
  # now and the honest sentence is carried by the DETAIL, which is still
  # derived — asserted below, with E5 still forbidding the ATTEMPTED claim. The
  # property `## BL-225:` won is unchanged; only which half of the message
  # carries it moved, and the design instructed the move.
  chk "E4 — labelled BLOCKED (a check ran), per docs/messaging-standard.md" \
    "$(grep -c '\[BLOCKED\]' "$E_ERR")" "1"
  chk "E4b — and the detail still says nothing was written" \
    "$([ "$(grep -ci 'nothing was written' "$E_ERR")" -ge 1 ] && echo yes || echo no)" "yes"
  chk "E5 — and never says adoption ATTEMPTED writes to this project" \
    "$(grep -ci 'ATTEMPTED writes' "$E_ERR")" "0"
fi

echo "=== S — the call is before the write, structurally ==="

# T6 — the stub in T1-T5 cannot prove ORDER. This does: in adopt_main the
# preflight's marked call must precede the real write phase's marked call.
_ln() { grep -n "$1" "$STATE" | head -1 | cut -d: -f1; }
pre_ln="$(_ln 'BL-225-PREWRITE-CALL$')"; wr_ln="$(_ln 'BL-225-WRITE-PHASE-REAL$')"
chk "T6: both marked calls exist" \
  "$([ -n "$pre_ln" ] && [ -n "$wr_ln" ] && echo yes || echo no)" "yes"
chk "T6: the preflight is called BEFORE the write phase" \
  "$([ -n "$pre_ln" ] && [ -n "$wr_ln" ] && [ "$pre_ln" -lt "$wr_ln" ] && echo yes || echo no)" "yes"

# T7 — one write phase, not two. The anti-drift claim is that the rehearsal and
# the real run share a writer; two definitions would defeat it.
chk "T7: _adopt_write_phase is defined exactly once" \
  "$(grep -c '^_adopt_write_phase() {' "$STATE")" "1"
chk "T7: and the archive/install/state writers live only inside it" \
  "$(grep -c '^  adopt_archive_write "\$root" "\$work"' "$STATE")" "1"

echo "=== M — markers and a mutation proof ==="

for m in 'BL-225-PREWRITE-CALL' 'BL-225-WRITE-PHASE-REAL' 'BL-225-PREWRITE-REFUSE'; do
  n="$(grep -c "# ${m}\$" "$STATE")"; case "$n" in ''|*[!0-9]*) n=0 ;; esac
  chk "M0: '# $m' occurs exactly once at end-of-line" "$n" "1"
done

# MP1 — delete the check-ignore arm on a mirror: T1 must stop refusing. Without
# this, T1 passes for any reason at all, including a preflight that refuses
# every project.
#
# The mutation is awk, not python3: the runner has python3 and a bare
# `ubuntu:24.04` does not, and this suite must give the same verdict on both.
# It rewrites a TWO-LINE anchor, so the edit cannot be a one-line sed; and it
# asserts the anchor was unique AND that the replacement LANDED, because "the
# mutator ran" is not "the mutant mutates".
MP="$WORK/mp/lib"; mkdir -p "$MP" && cp -p "$LIB"/*.sh "$MP/"
mp_anchor='      0) ignored="$ignored'
mp_tail='$rel" ;;'
mp_n="$(grep -cF "$mp_anchor" "$MP/adopt-state.sh")"; case "$mp_n" in ''|*[!0-9]*) mp_n=0 ;; esac
mp_t0="$(grep -cFx "$mp_tail" "$MP/adopt-state.sh")"; case "$mp_t0" in ''|*[!0-9]*) mp_t0=0 ;; esac
awk -v anchor="$mp_anchor" '
  $0 == anchor { print "      0) : ;;"; skip = 1; next }
  skip == 1    { skip = 0; next }
  { print }
' "$MP/adopt-state.sh" > "$MP/adopt-state.sh.mut" && mv "$MP/adopt-state.sh.mut" "$MP/adopt-state.sh"
mp_left="$(grep -cF "$mp_anchor" "$MP/adopt-state.sh")"; case "$mp_left" in ''|*[!0-9]*) mp_left=0 ;; esac
mp_new="$(grep -c '^      0) : ;;$' "$MP/adopt-state.sh")"; case "$mp_new" in ''|*[!0-9]*) mp_new=0 ;; esac
# The awk deletes the line AFTER the anchor unconditionally. Assert that line
# was the one intended: if the source ever changes so anchor+1 is something
# else, this mutator would silently delete an arbitrary line and could still
# satisfy the other three postconditions and `bash -n`.
mp_t1="$(grep -cFx "$mp_tail" "$MP/adopt-state.sh")"; case "$mp_t1" in ''|*[!0-9]*) mp_t1=0 ;; esac
if [ "$mp_n" -ne 1 ] || [ "$mp_left" -ne 0 ] || [ "$mp_new" -ne 1 ] \
   || [ "$mp_t0" -ne 1 ] || [ "$mp_t1" -ne 0 ] \
   || ! bash -n "$MP/adopt-state.sh" 2>/dev/null; then
  bad "MP1 setup: the mutation did not apply cleanly (anchors=$mp_n left=$mp_left new=$mp_new tail=$mp_t0->$mp_t1)"
else
  P9="$WORK/t9"; _adoptee "$P9" '.claude/'
  mp_rc=$( set +e
    ADOPT_PROJECT_NAME=t
    . "$MP/adopt-core.sh"  >/dev/null 2>&1
    . "$MP/adopt-state.sh" >/dev/null 2>&1
    ADOPT_WORK="$WORK/w.mp"; mkdir -p "$ADOPT_WORK"
    adopt_ledger_init "$ADOPT_WORK/written" >/dev/null 2>&1
    _adopt_write_phase() { adopt_record_write '.claude/manifest.json'; return 0; }
    adopt_prewrite_preflight "$P9" "" >/dev/null 2>&1; echo $? )
  chk "MP1 (MUTATION): without the oracle the ignored project is ALLOWED — T1 is what stops it" \
    "${mp_rc:-x}" "0"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0
exit 1

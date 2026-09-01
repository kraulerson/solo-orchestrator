#!/usr/bin/env bash
# tests/test-bl225-staging-preflight.sh — BL-225.
#
# THE DEFECT, reproduced in T1 rather than described: the driver writes its
# files, stages every recorded path in ONE `git add`, and `git add` on a mixed
# pathspec STAGES THE CLEAN ONES AND EXITS 1. The adoptee is left half-staged
# under a refusal that says "nothing has been committed" — true of commits,
# silent about the index.
#
# Measured here, not assumed (T1): with `.claude/` ignored, a three-path add
# leaves two paths in the index and returns 1.
#
# ── HOST GIT CONFIG IS NEUTRALIZED, AND IT HAS TO BE ────────────────────────
# Inherited verbatim from tests/test-brownfield-wp6-collision-archive.sh's
# R-WP6-3, which MEASURED the cause on this host: `~/.config/git/ignore`
# commonly carries `**/.claude/settings.local.json`, and it is found by a PATH
# default (`$XDG_CONFIG_HOME/git/ignore`), NOT by a config key — so
# GIT_CONFIG_GLOBAL does not cover it. XDG_CONFIG_HOME is the knob. A fixture
# whose verdict depends on whose laptop runs it is not a fixture.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_TEMPLATE_DIR
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
unset GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_COMMON_DIR
# The pathspec-magic family (R-WP6-18): with these set, `git check-ignore`
# dies "pathspec magic not supported by this command", and any probe that
# wraps it in 2>/dev/null scores the fatal as NOT IGNORED — fail-open. T5
# pins that the product code refuses instead.
unset GIT_LITERAL_PATHSPECS GIT_NOGLOB_PATHSPECS GIT_GLOB_PATHSPECS GIT_ICASE_PATHSPECS
unset GITHUB_BASE_REF        # house rule: fixture git ops must not see the runner's base ref

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  [PASS] $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  [FAIL] $1"; }
chk()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/bl225.XXXXXX")" || exit 1
# BL-244: mktemp must not silently land in the launch directory.
case "$WORK" in "$REPO_ROOT"*) echo "FATAL: fixture inside repo"; exit 1 ;; esac
trap 'rm -rf "$WORK"' EXIT INT TERM
# THE HEADER ABOVE CLAIMED THIS AND THE FIRST DRAFT NEVER DID IT. Review
# reproduced the gap: with a global excludes file carrying `.claude/`, the suite
# went 16 passed / 1 failed. GIT_CONFIG_GLOBAL does not cover the excludes file
# — it is found by a PATH default — so this is the knob, exactly as the header
# says. A header that describes a neutralization the file does not perform is
# worse than no header.
export XDG_CONFIG_HOME="$WORK/xdg"; mkdir -p "$XDG_CONFIG_HOME"
export HOME="$WORK/home"; mkdir -p "$HOME"

_adoptee() {                     # _adoptee DIR [ignore-line...]
  local d="$1"; shift
  mkdir -p "$d" && ( cd "$d" \
    && git init -q -b main . \
    && git config user.email t@example.com && git config user.name T \
    && printf 'their code\n' > README.md \
    && { [ "$#" -eq 0 ] || printf '%s\n' "$@" > .gitignore; } \
    && git add -A && git commit -q -m 'chore: their history' ) || return 1
}
_staged()  { ( cd "$1" && git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ' ); }
_sites()   { local n; n=$(grep -c "$2\$" "$1" 2>/dev/null); case "$n" in ''|*[!0-9]*) echo 0 ;; *) echo "$n" ;; esac; }
_parses_ok() { bash -n "$1" >/dev/null 2>&1 && echo 1 || echo 0; }

echo "== T1 — the defect itself: a mixed pathspec half-stages =="
P="$WORK/t1"; _adoptee "$P" '.claude/'
mkdir -p "$P/.claude"; printf 'a\n' > "$P/a.txt"; printf 'b\n' > "$P/b.txt"; printf 'c\n' > "$P/.claude/manifest.json"
( cd "$P" && git add -- a.txt b.txt .claude/manifest.json ) >/dev/null 2>&1; rc=$?
chk "T1: git add on a mixed pathspec exits non-zero" "$([ "$rc" -ne 0 ] && echo yes || echo no)" "yes"
chk "T1: and it staged the clean paths anyway (the half-staged tree)" "$(_staged "$P")" "2"

echo "== T0 — the TRACKED-path case: check-ignore says clean, git add refuses =="
# This is review finding 1, and it is why the oracle changed. A path that is
# TRACKED is invisible to `git check-ignore` (git-check-ignore(1): "tracked
# files are not shown at all"), but `git add` still refuses on its ignored
# leading directory — and stages the rest. The first fix keyed on check-ignore
# and therefore let BL-225 through unchanged on exactly this shape.
P0="$WORK/t0"; _adoptee "$P0"
mkdir -p "$P0/.claude"; printf 'x\n' > "$P0/.claude/manifest.json"; printf 'y\n' > "$P0/PROJECT_INTAKE.md"
( cd "$P0" && git add -A && git commit -q -m tracked && printf '.claude/\n' > .gitignore && git add .gitignore && git commit -q -m ign ) >/dev/null 2>&1
printf 'z\n' >> "$P0/.claude/manifest.json"; printf 'w\n' >> "$P0/PROJECT_INTAKE.md"
( cd "$P0" && printf '%s\n' ".claude/manifest.json" "PROJECT_INTAKE.md" | git check-ignore --stdin ) >/dev/null 2>&1
chk "T0: check-ignore reports the tracked path as NOT ignored (rc 1)" "$?" "1"
( cd "$P0" && git add --dry-run -- .claude/manifest.json PROJECT_INTAKE.md ) >/dev/null 2>&1
chk "T0: git add --dry-run DOES refuse it (the oracle that matches ground truth)" "$?" "1"

echo "== T2 — adopt_name_ignored_paths NAMES paths (it does not decide) =="
. "$REPO_ROOT/scripts/lib/adopt/adopt-core.sh" 2>/dev/null
if ! command -v adopt_name_ignored_paths >/dev/null 2>&1; then
  bad "T2: adopt_name_ignored_paths is not defined (RED before the fix)"
  bad "T2: (dependent assertions skipped)"; bad "T3: (skipped)"; bad "T4: (skipped)"; bad "T5: (skipped)"
else
  P2="$WORK/t2"; _adoptee "$P2" '.claude/'
  out="$(adopt_name_ignored_paths "$P2" "README.md" ".claude/manifest.json" 2>&1)"; rc=$?
  chk "T2: reports rc=0 when at least one path is ignored" "$rc" "0"
  chk "T2: and names the ignored path" "$(printf '%s' "$out" | grep -c 'manifest.json')" "1"
  chk "T2: and does NOT name the clean one" "$(printf '%s' "$out" | grep -c 'README.md')" "0"

  P3="$WORK/t3"; _adoptee "$P3"
  adopt_name_ignored_paths "$P3" "README.md" ".claude/manifest.json" >/dev/null 2>&1
  chk "T3: rc=1 when nothing is ignored" "$?" "1"

  echo "== T5 — a check-ignore that CANNOT RUN is not 'nothing is ignored' =="
  P5="$WORK/t5"; _adoptee "$P5" 'sub/*.txt'
  # GIT_NOGLOB_PATHSPECS makes check-ignore FATAL. A 2>/dev/null probe scores
  # that as clean; this must fail CLOSED instead (rc 0 = treat as ignored).
  # THE DECIDER IS IMMUNE TO THE HAZARD THAT BROKE THE OLD ONE, and that is a
  # stronger property than the fail-closed guard it replaced. `git check-ignore`
  # DIES (rc 128) under every pathspec-magic variable — the hazard
  # tests/test-brownfield-wp6-collision-archive.sh measured (R-WP6-18) — so any
  # probe wrapping it in 2>/dev/null scores the fatal as "clean". `git add
  # --dry-run` answers correctly under all three, so the fail-open class is
  # ELIMINATED here rather than defended against. Asserted in both directions:
  # the hazard must be real, or this case proves nothing.
  t5_ci_dead=0; t5_dry_ok=0
  for _v in GIT_NOGLOB_PATHSPECS GIT_LITERAL_PATHSPECS GIT_ICASE_PATHSPECS; do
    ( cd "$P5" && env "$_v=1" git check-ignore -q -- "README.md" ) >/dev/null 2>&1
    [ "$?" -eq 128 ] && t5_ci_dead=$((t5_ci_dead + 1))
    ( cd "$P5" && env "$_v=1" git add --dry-run -- "README.md" ) >/dev/null 2>&1
    [ "$?" -eq 0 ] && t5_dry_ok=$((t5_dry_ok + 1))
  done
  chk "T5: the hazard is REAL — check-ignore dies (128) under all 3 magic vars" "$t5_ci_dead" "3"
  chk "T5: and the chosen oracle is IMMUNE — --dry-run answers under all 3"     "$t5_dry_ok"  "3"
fi

echo "== T4 — the staging guard: refuse whole, never half =="
if ! grep -q '# BL-225-STAGE-PREFLIGHT' "$REPO_ROOT/scripts/lib/adopt/adopt-state.sh" 2>/dev/null; then
  bad "T4: # BL-225-STAGE-PREFLIGHT marker absent (RED before the fix)"
else
  ok "T4: # BL-225-STAGE-PREFLIGHT marker present in adopt_stage_and_commit"
  chk "T4: the guard precedes the git add" \
    "$(awk '/# BL-225-STAGE-PREFLIGHT/{g=NR} /BF-ADOPT-STAGE-EXPLICIT/{a=NR} END{print (g && a && g<a) ? "yes" : "no"}' "$REPO_ROOT/scripts/lib/adopt/adopt-state.sh")" "yes"
  # NOT a grep of adopt-state.sh: the sentence never lived there, so that
  # assertion was true of the unfixed tree too. The claim is adopt_refuse's,
  # in adopt-core.sh, and it is asserted by BEHAVIOUR.
  chk "T4: adopt_refuse no longer states the bare unconditional claim" \
    "$(_sites "$REPO_ROOT/scripts/lib/adopt/adopt-core.sh" "Adoption did not complete. Nothing has been committed.\\\\n' >&2")" "0"
fi

echo "== T6 — adopt_stage_and_commit refuses WHOLE: rc!=0 and index untouched =="
_stage_fixture() {                # $1 = dir
  local p="$1"
  _adoptee "$p" '.claude/' || return 1
  mkdir -p "$p/.claude"
  printf 'a\n' > "$p/keep-a.txt"; printf 'b\n' > "$p/keep-b.txt"
  printf '{}\n'  > "$p/.claude/manifest.json"
  printf 'keep-a.txt\nkeep-b.txt\n.claude/manifest.json\n' > "$p/.ledger"
}
_run_stage() {                    # $1 = dir, $2 = lib dir -> "rc|staged|stderr"
  ( set +e
    ADOPT_PROJECT_NAME=t
    . "$2/adopt-core.sh"  >/dev/null 2>&1
    . "$2/adopt-state.sh" >/dev/null 2>&1
    # SET THE LEDGER **AFTER** SOURCING. adopt-core.sh declares
    # ADOPT_WRITTEN_LEDGER="" at load time, so an earlier draft that set it
    # first had it silently wiped: the ledger read empty, adopt_stage_and_commit
    # took its "nothing to commit" arm, and T6's rc!=0 / staged==0 assertions
    # passed FOR THE WRONG REASON — both are equally true of an empty ledger.
    # M2 exposed it, because mutant and control produced identical output.
    # Hence the stderr discriminator: rc and a count cannot tell the two
    # refusals apart, and only one of them is this suite's subject.
    ADOPT_WRITTEN_LEDGER="$1/.ledger"
    err=$(adopt_stage_and_commit "$1" 2>&1 >/dev/null); rc=$?
    printf '%s|%s|%s\n' "$rc" \
      "$( cd "$1" && git diff --cached --name-only | wc -l | tr -d ' ' )" \
      "$(printf '%s' "$err" | tr '\n' ' ')" )
}
P6="$WORK/t6"; _stage_fixture "$P6"
IFS='|' read -r t6rc t6staged t6err <<<"$(_run_stage "$P6" "$REPO_ROOT/scripts/lib/adopt")"
chk "T6: refuses (rc != 0)"                        "$([ "${t6rc:-0}" -ne 0 ] && echo yes || echo no)" "yes"
chk "T6: and stages NOTHING (no half-staged tree)" "${t6staged:-x}" "0"
# POSITIVE CONTROLS. Without these the two assertions above are equally true of
# an EMPTY ledger, which is how they first passed against unfixed code.
chk "T6: refused via the PREFLIGHT, naming the ignored path" "$(printf '%s' "$t6err" | grep -c 'manifest.json')" "1"
chk "T6: not via the empty-ledger arm"                       "$(printf '%s' "$t6err" | grep -c 'no file was recorded as written')" "0"

echo "== T8 — the ignored path is NOT first, at the DECIDER =="
# Review finding 4 was fixed at the NAMER (T2/T3's argument order) — and the
# namer is no longer the decider. Every other fixture here sorts `.claude/...`
# to index 0, so a decider that examined only FILES_TO_STAGE[0] passed the whole
# suite 24/24 while half-staging. This fixture puts the offending path at index
# a non-zero one: `.gitignore` excludes PROJECT_INTAKE.md. Where exactly it
# lands depends on the host's collation — see the derivation below — so this
# comment deliberately does not name an index.
P8="$WORK/t8"; _adoptee "$P8" 'PROJECT_INTAKE.md'
mkdir -p "$P8/.claude"
printf '{}\n'  > "$P8/.claude/manifest.json"
printf 'i\n'   > "$P8/PROJECT_INTAKE.md"
printf 'k\n'   > "$P8/keep.txt"
printf '.claude/manifest.json\nPROJECT_INTAKE.md\nkeep.txt\n' > "$P8/.ledger"
# DERIVE the index, never hardcode it: `sort` is LOCALE-DEPENDENT. On this host
# the collation is case-insensitive and PROJECT_INTAKE.md lands at 3; under a
# C-locale runner it lands at 2. Pinning either number makes the fixture pass on
# one machine and fail on the other — the local-vs-CI divergence class CLAUDE.md
# warns about. The PROPERTY this fixture needs is only "not first".
t8_idx=$(cd "$P8" && sort -u .ledger | grep -n '^PROJECT_INTAKE.md$' | cut -d: -f1)
chk "T8: the offending path is NOT at index 1 (derived: $t8_idx)" \
  "$([ "${t8_idx:-1}" -gt 1 ] && echo not-first || echo first)" "not-first"
IFS='|' read -r t8rc t8staged t8err <<<"$(_run_stage "$P8" "$REPO_ROOT/scripts/lib/adopt")"
chk "T8: refuses"                                   "$([ "${t8rc:-0}" -ne 0 ] && echo yes || echo no)" "yes"
chk "T8: and stages NOTHING — the decider sees the WHOLE set, not just [0]" "${t8staged:-x}" "0"
chk "T8: git's force hint is never relayed"         "$(printf '%s' "$t8err" | grep -c 'really want to add them')" "0"
chk "T8: and the remedy line is present"            "$(printf '%s' "$t8err" | grep -c 'Un-ignore them in .gitignore')" "1"

echo "== T9 — a NET over the write shapes we know. Not a proof. =="
# THE INVARIANT IS TESTED BECAUSE ASSERTING IT FAILED — TWICE, IN DIFFERENT WAYS.
# First the flag's comment claimed "ANY writer" while it was set at two of
# twelve sites. Then this check's own recipe was an ALLOWLIST of specific
# variable spellings ("$dir", "$dst", "$arc_abs", ...), so review added an
# ordinary new function writing to "$dest" and the check reported all clear.
# A transcribed set is not a derived one; that is this repo's own rule and this
# guard broke it.
#
# So the recipe is now a DENYLIST: match the general SHAPES that write, then
# subtract an explicit, commented allowlist of lines whose target is not the
# adoptee's tree. A new writer is caught by default, and an exemption has to be
# written down with a reason — the shape `lint-bl-markers.sh` already uses.
#
# WHAT THIS STILL CANNOT DO, stated rather than implied: it checks that a
# marker call appears before the write inside the same function. It does NOT
# check reachability — a call wrapped in a never-true condition would satisfy
# it. Reachability is not statically decidable here; the mitigation is that the
# marker is a FILE, so a placed-but-unreachable call creates nothing and the
# behavioural tests (T7, the archive probe) fail instead.
_writers() {
  # One grep per verb, not one giant alternation: a single ERE with a dozen
  # alternatives silently matched fewer lines than its own first alternative
  # while this was being built, and a recipe nobody can debug is a recipe
  # nobody can trust.
  # BOTH loops must feed the SAME pipeline. A first draft left the first loop
  # un-piped, so its output bypassed every filter and comments came back as
  # writers — the filters were there and simply were not reached.
  { for _v in 'mkdir -p ' 'cp ' 'mv ' 'install ' 'ln ' 'touch ' 'cat > '; do
      # WORD-BOUNDED: `grep -F 'touch '` matched `n_touch ` inside a `local`
      # declaration — a variable name, not a command.
      grep -rnE -- "(^|[^A-Za-z0-9_])$_v" "$REPO_ROOT"/scripts/lib/adopt/*.sh
    done
    for _v in '> "$' '>> "$'; do
      grep -rnF -- "$_v" "$REPO_ROOT"/scripts/lib/adopt/*.sh
    done; } \
    | grep -vE ':[0-9]+: *#' \
    | grep -vE ':[0-9]+:[[:space:]]*(adopt_note|adopt_say|adopt_head|adopt_refuse|printf|echo)([[:space:]]|$)' \
    | grep -vE '\$ADOPT_WORK|\$TD_TMP|\$TMPDIR|mktemp|\$ADOPT_WRITTEN_LEDGER' \
    | grep -vE '"\$work/|"\$ADOPT_ANSWERS"|> "\$names"' \
    | cut -d: -f1,2 | sort -u
}
# ^ THE ALLOWLIST, and every arm carries its reason:
#   :N: #        — a comment describing a write is not a write
#   a line whose FIRST TOKEN is an output function
#                — output functions whose ARGUMENTS contain write verbs
#                  ("put it back: cp $arc/$ap $op"). Anchored to the first
#                  token on purpose: a draft that excluded any line CONTAINING
#                  `adopt_refuse "` removed nearly every real writer, because
#                  almost all of them end `|| { adopt_refuse "..."; return 1; }`.
#                  The writer count collapsed from 25 to 1 and the check went
#                  green on nothing.
#   $ADOPT_WORK / $TD_TMP / $TMPDIR / mktemp / the written-ledger
#                — the driver's own state, not the operator's tree.
#                  `/dev/null` IS DELIBERATELY ABSENT: excluding it removed
#                  almost every real writer, because nearly all of them carry
#                  `2>/dev/null` for error suppression. The writer set silently
#                  collapsed to five while the check stayed green — the same
#                  shape as the allowlist it replaced, arriving through an
#                  exclusion instead of an omission.
#   "$work/ , "$ADOPT_ANSWERS" , > "$names"
#                — THREE NAMED EXEMPTIONS, named because they cannot be derived
#                  from the line itself: `$work` and `$ADOPT_ANSWERS` arrive as
#                  PARAMETERS (`local arc="$1" work="$2"`; `ADOPT_ANSWERS="$1"`)
#                  and `$names` is assigned `"$TD_TMP/names"` a line earlier.
#                  All three are driver scratch, not the adoptee's tree, and
#                  tracing callers is beyond what a shell fixture should do.
#                  AN EXEMPTION MUST ALWAYS CARRY A REASON LIKE THESE — that is
#                  the whole difference between this denylist and the allowlist
#                  it replaced, where an unrecognised target was silently absent
#                  instead of loudly flagged.
#
# WHAT THIS IS AND IS NOT — AND THIS PARAGRAPH IS THE FINDING, NOT A CAVEAT.
# This check has been rewritten twice and defeated twice, each rewrite opening a
# new blind spot of the same shape. That is evidence about the APPROACH: **a
# shell regex cannot decide "does this line write into the adoptee's tree",
# because the answer depends on variable provenance the line does not carry.**
# `printf x > "$root/f"` and `printf x > "$TD_TMP/f"` are the same shape and
# opposite answers. So this stopped being rewritten, and is instead labelled
# honestly and paired with a cross-check that does not depend on the recipe
# being complete (T10). Known gaps, recorded on `## BL-225:` rather than
# papered over: `printf … > file` and `echo … > file` (the output-function arm
# removes them, and it must, or it removes nearly every real writer instead);
# `tee`; a redirect with no space after `>`; and an exemption matching on the
# READ side of a line whose write target is in the tree.
#
# It is a NET, not a proof. It catches a new writer
# that uses any of the shapes above, which is how review defeated the previous
# recipe — an ordinary new function writing to `"$dest"`. It does NOT verify
# REACHABILITY: a marker call wrapped in a never-true condition would satisfy
# it, and that is not statically decidable here. The mitigation is structural
# rather than textual — the marker is a FILE, so a placed-but-unreachable call
# creates nothing and the BEHAVIOURAL assertions (T7, and the archive probe)
# fail instead. Recorded on `## BL-225:` as a residual rather than implied.
_marker_files() {   # files that call the marker, by basename
  grep -rlE '(^|[^A-Za-z0-9_])adopt_touched_disk([^A-Za-z0-9_]|$)' "$REPO_ROOT"/scripts/lib/adopt/*.sh \
    | xargs -n1 basename | sort -u
}
_writer_files() {   # files the recipe believes contain writers, by basename
  _writers | cut -d: -f1 | xargs -n1 basename | sort -u
}
t9_w=$(_writers | wc -l | tr -d ' ')
chk "T9: the recipe still matches tree-writing sites at all" \
  "$([ "${t9_w:-0}" -gt 0 ] && echo yes || echo no)" "yes"
# For each writer, scan back to the start of its enclosing function and require
# a marker call in between. PER-FUNCTION, not per-writer: two adjacent writers
# cannot both carry a line above them without a redundant one, and removing a
# redundant one is a genuine no-op. Measured both directions — see below.
t9_missing=0
while IFS=: read -r wf wl; do
  [ -n "$wl" ] || continue
  fn_start=$(awk -v L="$wl" 'NR<L && /^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ {n=NR} END{print n+0}' "$wf")
  [ "$fn_start" -gt 0 ] || fn_start=1
  if ! awk -v A="$fn_start" -v B="$wl" 'NR>A && NR<B && /adopt_touched_disk/ {f=1} END{exit !f}' "$wf"; then
    t9_missing=$((t9_missing + 1))
    echo "         (T9) no marker before $(basename "$wf"):$wl in its function"
  fi
done <<T9SET
$(_writers)
T9SET
chk "T9: every tree-writing site is preceded by the marker (writers=$t9_w)" "$t9_missing" "0"

echo "== T10 — the recipe cannot collapse silently (two independently derived sets) =="
# T9's weakness is that it can only fail on writers it FINDS. Twice now the
# recipe has silently stopped finding almost everything — once via a `/dev/null`
# exclusion that matched `2>/dev/null` on nearly every writer, once via an
# `adopt_refuse "` exclusion that matched their error tails — and T9 stayed
# green over a collapsed set both times. `t9_w > 0` cannot see that.
#
# This compares two sets derived INDEPENDENTLY: files that call the marker, and
# files the recipe believes contain writers. A file that raises the marker but
# yields no writer means the recipe stopped seeing that file. No transcribed
# number is involved, so it cannot rot.
t10_bad=0
for _mf in $(_marker_files); do
  _writer_files | grep -qx "$_mf" || { t10_bad=$((t10_bad + 1)); echo "         (T10) $_mf calls the marker but the recipe finds no writer in it"; }
done
chk "T10: every file that raises the marker also yields a writer" "$t10_bad" "0"

# ORDER-SENSITIVE: M2 and M3 each `cp` their own mutant over
# "$MUTLIB/adopt-state.sh". Correct at the current ordering because each writes
# immediately before it runs, but a reorder would silently run one mutation
# against the other's file. A third mutant needs its own path.
echo "== M — mutation proofs =="
MUTLIB="$WORK/mutlib"; mkdir -p "$MUTLIB"
cp "$REPO_ROOT/scripts/lib/adopt/adopt-core.sh" "$MUTLIB/adopt-core.sh"

# The TRACKED-path fixture: this is the shape finding 1 was found on, and the
# shape a real adoptee takes once a `.claude/` rule is added after adoption.
_tracked_fixture() {
  local p="$1"
  _adoptee "$p" || return 1
  mkdir -p "$p/.claude"
  printf 'x\n' > "$p/.claude/manifest.json"; printf 'y\n' > "$p/PROJECT_INTAKE.md"
  ( cd "$p" && git add -A && git commit -q -m tracked \
      && printf '.claude/\n' > .gitignore && git add .gitignore && git commit -q -m ign ) >/dev/null 2>&1 || return 1
  printf 'z\n' >> "$p/.claude/manifest.json"; printf 'w\n' >> "$p/PROJECT_INTAKE.md"
  printf '.claude/manifest.json\nPROJECT_INTAKE.md\n' > "$p/.ledger"
}

# M1 — THE ORACLE. Put the refuted oracle back and the tracked fixture
# half-stages again. This is the mutation that pins review finding 1; the
# suite's first version had no assertion that could see it.
# Restore the refuted oracle WITH ITS ORIGINAL POLARITY: the first fix asked
# "is anything ignored?" and refused on yes. On a TRACKED path check-ignore
# answers no, so the mutant falls through to `git add` and half-stages — which
# is the defect, reproduced on demand. (A first draft of this mutation kept the
# `!` and so inverted the predicate instead of restoring it: the mutant refused
# everything and "staged=0" looked like a pass. Restore the shape, not the tool.)
sed 's|^  if ! _dry=$( cd "$root" && git add --dry-run -- "${FILES_TO_STAGE\[@\]}" 2>&1 >/dev/null ); then$|  if _ignored=$(adopt_name_ignored_paths "$root" "${FILES_TO_STAGE[@]}"); then|' \
  "$REPO_ROOT/scripts/lib/adopt/adopt-state.sh" > "$MUTLIB/adopt-state.sh"
n1=$(diff "$REPO_ROOT/scripts/lib/adopt/adopt-state.sh" "$MUTLIB/adopt-state.sh" | grep -c '^<')
if [ "$n1" -ne 1 ]; then bad "M1: oracle mutation did not apply (changed $n1 line(s))"
elif [ "$(_parses_ok "$MUTLIB/adopt-state.sh")" != "1" ]; then bad "M1: mutant does not parse"
else
  PM1="$WORK/m1"; _tracked_fixture "$PM1"
  IFS='|' read -r m1rc m1staged m1err <<<"$(_run_stage "$PM1" "$MUTLIB")"
  chk "M1: with check-ignore as the oracle the TRACKED fixture half-stages (RED)" \
    "$([ "${m1staged:-0}" -gt 0 ] && echo half-staged || echo "staged=${m1staged}")" "half-staged"
fi

# M2 — THE GUARD ITSELF. Remove the preflight entirely; the same fixture
# half-stages. Distinct from M1: M1 proves the ORACLE matters, M2 proves the
# GUARD does.
sed 's|^  if ! _dry=$( cd "$root" && git add --dry-run -- "${FILES_TO_STAGE\[@\]}" 2>&1 >/dev/null ); then$|  if false; then|' \
  "$REPO_ROOT/scripts/lib/adopt/adopt-state.sh" > "$MUTLIB/adopt-state2.sh"
n2=$(diff "$REPO_ROOT/scripts/lib/adopt/adopt-state.sh" "$MUTLIB/adopt-state2.sh" | grep -c '^<')
if [ "$n2" -ne 1 ]; then bad "M2: guard mutation did not apply (changed $n2 line(s))"
elif [ "$(_parses_ok "$MUTLIB/adopt-state2.sh")" != "1" ]; then bad "M2: mutant does not parse"
else
  cp "$MUTLIB/adopt-state2.sh" "$MUTLIB/adopt-state.sh"
  PM2="$WORK/m2"; _stage_fixture "$PM2"
  IFS='|' read -r m2rc m2staged m2err <<<"$(_run_stage "$PM2" "$MUTLIB")"
  chk "M2: without the preflight the SAME fixture HALF-STAGES (RED)" \
    "$([ "${m2staged:-0}" -gt 0 ] && echo half-staged || echo "staged=${m2staged} err=${m2err}")" "half-staged"
  chk "M2: and the mutant reached git add, not the empty-ledger arm" \
    "$(printf '%s' "$m2err" | grep -c 'no file was recorded as written')" "0"
fi

# M3 — THE DECIDER'S ARGUMENT SET. Feed the dry-run only the first path; the
# M1/M2 sed anchors are left byte-identical so their guards do not fire instead.
sed 's|git add --dry-run -- "${FILES_TO_STAGE\[@\]}" 2>&1 >/dev/null|git add --dry-run -- "${FILES_TO_STAGE[0]}" 2>\&1 >/dev/null|' \
  "$REPO_ROOT/scripts/lib/adopt/adopt-state.sh" > "$MUTLIB/adopt-state3.sh"
n3=$(diff "$REPO_ROOT/scripts/lib/adopt/adopt-state.sh" "$MUTLIB/adopt-state3.sh" | grep -c '^<')
if [ "$n3" -ne 1 ]; then bad "M3: mutation did not apply (changed $n3 line(s))"
elif [ "$(_parses_ok "$MUTLIB/adopt-state3.sh")" != "1" ]; then bad "M3: mutant does not parse"
else
  cp "$MUTLIB/adopt-state3.sh" "$MUTLIB/adopt-state.sh"
  PM3="$WORK/m3"; _adoptee "$PM3" 'PROJECT_INTAKE.md'
  mkdir -p "$PM3/.claude"; printf '{}\n' > "$PM3/.claude/manifest.json"
  printf 'i\n' > "$PM3/PROJECT_INTAKE.md"; printf 'k\n' > "$PM3/keep.txt"
  printf '.claude/manifest.json\nPROJECT_INTAKE.md\nkeep.txt\n' > "$PM3/.ledger"
  IFS='|' read -r m3rc m3staged m3err <<<"$(_run_stage "$PM3" "$MUTLIB")"
  chk "M3: a decider reading only FILES_TO_STAGE[0] half-stages (RED)" \
    "$([ "${m3staged:-0}" -gt 0 ] && echo half-staged || echo "staged=${m3staged}")" "half-staged"
fi

# T7 — the real code on the tracked fixture: refuses, stages nothing.
PT7="$WORK/t7"; _tracked_fixture "$PT7"
IFS='|' read -r t7rc t7staged t7err <<<"$(_run_stage "$PT7" "$REPO_ROOT/scripts/lib/adopt")"
chk "T7: the TRACKED case now refuses (rc != 0)"     "$([ "${t7rc:-0}" -ne 0 ] && echo yes || echo no)" "yes"
chk "T7: and stages NOTHING — BL-225 no longer reproduces" "${t7staged:-x}" "0"
chk "T7: labelled BLOCKED, not REFUSED (files were written)" "$(printf '%s' "$t7err" | grep -c 'BLOCKED')" "1"
chk "T7: and it does not promise plain \`git status\` lists them" \
  "$(printf '%s' "$t7err" | grep -c 'git status --ignored --untracked-files=all')" "1"
# The TRACKED case is this branch's headline case and had NO message assertion,
# so the remedy could go missing there while T8's untracked fixture stayed
# green. `git check-ignore` is index-aware and cannot name a tracked path, so
# gating the remedy on the namer alone skipped exactly here.
chk "T7: the remedy is present on the TRACKED case too" \
  "$(printf '%s' "$t7err" | grep -c 'Un-ignore them in .gitignore')" "1"
chk "T7: and git's force hint is not relayed" \
  "$(printf '%s' "$t7err" | grep -c 'really want to add them')" "0"

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

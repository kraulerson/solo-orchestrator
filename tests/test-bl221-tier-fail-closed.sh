#!/usr/bin/env bash
# tests/test-bl221-tier-fail-closed.sh
#
# BL-221 — `assert_choosable` fails OPEN on a manifest with no `deployment`
# key, so an adopted organizational project can downgrade its own enforcement.
#
# THE PREDICATE, and why `//` is the whole bug:
#
#   deployment=$(jq -r '.deployment // "personal"' "$manifest")
#   if [ "$deployment" = "personal" ]; then return 0; fi
#
# jq's `//` coerces `null`, `false` AND `empty` to its right-hand side, so an
# ABSENT key and an EXPLICIT null both resolve to `personal` — the CHOOSABLE
# tier. This is the surface that decides whether a project may weaken its own
# enforcement, and it defaults to the permissive answer on missing data.
#
# ITS SIBLING IN THE SAME FILE FAILS CLOSED. `read_enforcement_level` treats a
# missing file, an unreadable one and an unknown value as `strict`. Two readers,
# one library, opposite postures on the same manifest — A8 pins that they now
# agree.
#
# THE DECISIVE CASE IS A3, and it is the entry's case C reproduced: take an
# organizational manifest that correctly REFUSES the downgrade, delete one key,
# change nothing else, and it starts ALLOWING it.
#
# WHY ADOPTION IS THE TRIGGER. The two birth paths write different manifests:
#
#   key                 init.sh        adopt-project.sh
#   deployment          "personal"     ABSENT
#   poc_mode            null           ABSENT
#   enforcement_level   "strict"       ABSENT
#
# and `reconfigure-project.sh` — which calls `validate_transition` ->
# `assert_choosable` — ships into every adopted project. So this is reachable
# from an operator command, not a library curiosity. W1 pins the write half.
#
# BOTH HALVES ARE FIXED HERE, on Karl's decision. Writing the keys closes the
# divergence at its source; defaulting the predicate closed fixes every OTHER
# cause of an absent key — a hand-edited manifest, or the regenerate path that
# `soif_adoption_integrity_lost` exists to detect — and makes the library
# self-consistent. Neither subsumes the other.
#
# EVIDENCE THAT THE WORKAROUND ALREADY EXISTS DOWNSTREAM: `_td_tier_trusted` in
# scripts/lib/adopt/adopt-test-debt.sh already adds its own presence check
# before trusting `assert_choosable`, and its comment says so ("this adds a
# presence check, not a fifth spelling"). A caller defending itself against a
# shared predicate is the predicate's bug, not the caller's.
#
# Hermetic: temp dirs only, no network, no init.sh. bash 3.2 safe.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENFLIB="$REPO_ROOT/scripts/lib/enforcement-level.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "  [SKIP] jq is not installed — this suite asserts on manifest state."
  echo ""; echo "Results: 0 passed, 0 failed"; exit 0
fi

TOPTMP="$(mktemp -d)"
trap 'chmod -R u+rwX "$TOPTMP" 2>/dev/null; rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/caseXXXXXX"; }

_num() { case "$1" in ''|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$1" ;; esac }
_mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || printf '?\n'; }
_sites() { local n; n=$(grep -c "$2\$" "$1" 2>/dev/null); _num "$n"; }
_changed_lines() { local n; n=$(diff "$1" "$2" 2>/dev/null | grep -c '^[<>]'); _num "$n"; }

#
# THE DELIMITER IS \001. `%` was the delimiter here until its sibling suite
# proved the class live: a mutant containing `printf %s` produced `bad flag in
# substitute command`, the file was left untouched, and the case reported
# `sites=0` — a mutation proof that proved nothing. `|` is worse (shell
# replacements are `||`-dense) and `@` collides with plugin ids. A control
# character cannot occur in a shell one-liner, so the class is closed rather
# than dodged. Today's replacements happen to contain no `%`; this is changed
# because the NEXT one might.
_mutate() {
  local f="$1" marker="$2" repl="$3" before sites changed parses safe mode tmp d
  d=$(printf '\001')
  safe=$(printf '%s' "$repl" | sed 's/&/\\&/g')
  mode="$(_mode_of "$f")"
  before="$(mktemp)"; cp -p "$f" "$before"
  sites=$(_sites "$f" "$marker")
  tmp="$(mktemp)"
  sed "s${d}^.*${marker}\$${d}${safe}${d}" "$f" > "$tmp" && mv "$tmp" "$f"
  [ "$mode" != "?" ] && chmod "$mode" "$f" 2>/dev/null
  changed=$(_changed_lines "$before" "$f")
  parses=0; bash -n "$f" >/dev/null 2>&1 && parses=1
  rm -f "$before"
  printf '%s %s %s\n' "$sites" "$changed" "$parses"
}

# mk_manifest <dir> <json> — a project root whose manifest is exactly <json>.
mk_manifest() {
  local d="$1" json="$2"
  mkdir -p "$d/.claude"
  printf '%s\n' "$json" > "$d/.claude/manifest.json"
}

# choosable <dir> [lib] — rc of assert_choosable, and CHOOSE_ERR its stderr.
CHOOSE_ERR=""
choosable() {
  local d="$1" lib="${2:-$ENFLIB}" rc=0
  CHOOSE_ERR="$(
    # shellcheck disable=SC1090
    . "$lib" 2>/dev/null
    assert_choosable "$d" 2>&1 >/dev/null
  )" || rc=$?
  return $rc
}

echo "=== A — the predicate fails CLOSED on absent tier data ==="

# ── A1: no `deployment` key at all. This is the shape adopt-project.sh writes.
A1="$(newtmp)"; mk_manifest "$A1" '{"host":"github","mode":"personal"}'
if choosable "$A1"; then a1=allowed; else a1=refused; fi
if [ "$a1" = "refused" ]; then
  pass "A1: a manifest with NO deployment key is REFUSED — the shape adopt-project.sh writes no longer resolves to the choosable tier by default"
else
  fail_ "A1" "assert_choosable ALLOWED a manifest with no deployment key (jq's // coerced the absent key to 'personal')"
fi

# ── A2: an EXPLICIT null. jq's `//` treats null and absent identically, so a
# fix that only checks for a missing key would leave this one open.
A2="$(newtmp)"; mk_manifest "$A2" '{"deployment":null,"poc_mode":null}'
if choosable "$A2"; then a2=allowed; else a2=refused; fi
if [ "$a2" = "refused" ]; then
  pass "A2: an EXPLICIT \"deployment\": null is refused too — jq's // coerces null and absent alike, so both must be caught by the same guard"
else
  fail_ "A2" "explicit null was ALLOWED; a fix keyed only on key-absence does not close this"
fi

# ── A3: THE FINDING. The entry's case C: one key removed from an
# organizational manifest, nothing else changed.
A3="$(newtmp)"
mk_manifest "$A3/full" '{"deployment":"organizational","poc_mode":"production","enforcement_level":"strict"}'
mk_manifest "$A3/minus" '{"poc_mode":"production","enforcement_level":"strict"}'
if choosable "$A3/full"; then a3_full=allowed; else a3_full=refused; fi
if choosable "$A3/minus"; then a3_minus=allowed; else a3_minus=refused; fi
if [ "$a3_full" = "refused" ] && [ "$a3_minus" = "refused" ]; then
  pass "A3: deleting ONE key from an organizational manifest no longer flips it from refused to allowed — both answer '$a3_full'. This is the entry's case C, and it was the finding"
else
  fail_ "A3" "organizational=$a3_full, organizational-minus-deployment=$a3_minus — a project that refuses to weaken its enforcement starts allowing it when one key goes missing"
fi

echo "=== B — the tiers that MUST still work are unchanged ==="

# ── B1: personal is still choosable. Without this the fix could pass by
# refusing everything, which is the over-tightening failure mode.
B1="$(newtmp)"; mk_manifest "$B1" '{"deployment":"personal","poc_mode":null}'
if choosable "$B1"; then
  pass "B1: deployment=personal is still CHOOSABLE — the fix refuses absent data, not every project"
else
  fail_ "B1" "a legitimate personal project can no longer choose its enforcement level; the guard is over-tightened"
fi

# ── B2: organizational + private_poc stays choosable (BL-129's carve-out).
B2="$(newtmp)"; mk_manifest "$B2" '{"deployment":"organizational","poc_mode":"private_poc"}'
if choosable "$B2"; then
  pass "B2: organizational + private_poc is still choosable — BL-129's carve-out survives"
else
  fail_ "B2" "BL-129's organizational+private_poc carve-out was broken by this change"
fi

# ── B3: organizational + production is still refused (the control).
B3="$(newtmp)"; mk_manifest "$B3" '{"deployment":"organizational","poc_mode":"production"}'
if choosable "$B3"; then
  fail_ "B3" "organizational+production is CHOOSABLE — the forced-strict tier is broken"
else
  pass "B3: organizational + production is still refused — the forced-strict tier is intact"
fi

echo "=== C — the refusal is actionable, and the library agrees with itself ==="

# ── C1: a refusal an operator cannot act on is a dead end. The message must
# name the missing key AND how to supply it.
C1="$(newtmp)"; mk_manifest "$C1" '{"host":"github"}'
choosable "$C1" || true
c1_names_key=no;  printf '%s' "$CHOOSE_ERR" | grep -q 'deployment' && c1_names_key=yes
c1_actionable=no; printf '%s' "$CHOOSE_ERR" | grep -qiE 'reconfigure|adopt|backfill|set|add' && c1_actionable=yes
if [ "$c1_names_key" = "yes" ] && [ "$c1_actionable" = "yes" ]; then
  pass "C1: the refusal names the missing key and tells the operator what to do — a blocking predicate that will not say why is its own defect"
else
  fail_ "C1" "names-key=$c1_names_key actionable=$c1_actionable err='$(printf '%s' "$CHOOSE_ERR" | tr '\n' '|' | cut -c1-200)'"
fi

# ── C2: POSTURE AGREEMENT. read_enforcement_level already failed closed on the
# same input; the two now answer the same way about the same manifest.
C2="$(newtmp)"; mk_manifest "$C2" '{"host":"github"}'
c2_level="$( . "$ENFLIB" 2>/dev/null; read_enforcement_level "$C2" )"
if choosable "$C2"; then c2_choose=allowed; else c2_choose=refused; fi
if [ "$c2_level" = "strict" ] && [ "$c2_choose" = "refused" ]; then
  pass "C2: on one absent-key manifest both readers now fail closed — read_enforcement_level says '$c2_level' and assert_choosable says '$c2_choose'. Two readers in one library disagreeing about the same file was half the finding"
else
  fail_ "C2" "read_enforcement_level=$c2_level (want strict) assert_choosable=$c2_choose (want refused)"
fi

echo "=== W — adoption writes the tier keys, so the divergence has no source ==="

# ── W1: the adopted manifest carries the same tier keys a scaffolded one does.
# Asserted on the WRITER's shipped code, not on a copy of it.
#
# COMMENTS ARE STRIPPED FIRST, AND THAT IS THE WHOLE POINT OF THIS BLOCK. The
# first version of W1 grepped the file whole — and `# BL-221-ADOPT-TIER-KEYS`'s
# own explanatory comment names all three keys, in prose, three lines above the
# jq filter. So the check passed on a tree where the fix had been reverted and
# only the comment survived: it was measuring that someone had once written
# about the keys, not that the writer writes them. Reading executed lines only
# is the same correction `# BL-181-UNIT-LANE-PREDICATE` made to the unit-lane
# exemption, for the same reason.
#
# IT TOOK THREE NARROWINGS TO STOP BEING VACUOUS, and M2 measured each one.
#   1. Whole file, bare word — satisfied by the fix's own COMMENT, which names
#      all three keys in prose three lines above the filter.
#   2. Comments stripped, bare word — satisfied by the SHELL VARIABLES
#      `$ADOPT_DEPLOYMENT` and `$ADOPT_POC_MODE` on executed lines; only
#      `enforcement_level`, which has no matching variable, could fail.
#   3. Comments stripped, key-assignment form (`.deployment =` / `deployment:`)
#      — satisfied by `adopt_write_phase_state`, which legitimately writes the
#      same three keys to a DIFFERENT file.
# So the scope is `adopt_write_manifest`'s body and the pattern is the
# key-assignment form. M2 now requires ALL THREE to go missing, which is the
# only version of this assertion that a reverted manifest writer cannot survive.
W1_SRC="$(newtmp)/adopt-state.exec"
awk '/^adopt_write_manifest\(\)/{i=1} i{print} i&&/^}/{exit}' \
  "$REPO_ROOT/scripts/lib/adopt/adopt-state.sh" | sed -e 's/[[:space:]]*#.*$//' > "$W1_SRC"
[ -s "$W1_SRC" ] || { fail_ "W1" "could not extract adopt_write_manifest from adopt-state.sh — the scope this case asserts in is empty, which would make it pass on anything"; }
W1_missing=""
for k in deployment poc_mode enforcement_level; do
  grep -Eq "[.]${k}[[:space:]]*=|${k}:" "$W1_SRC" || W1_missing="$W1_missing $k"
done
w1_marked=$(_num "$(grep -c 'BL-221-ADOPT-TIER-KEYS' "$REPO_ROOT/scripts/lib/adopt/adopt-state.sh" 2>/dev/null)")
if [ -z "$W1_missing" ] && [ "$w1_marked" -ge 1 ]; then
  pass "W1: adopt_write_manifest writes the tier keys (# BL-221-ADOPT-TIER-KEYS) — the two birth paths now produce the same manifest shape, which is where the divergence came from"
else
  fail_ "W1" "adopt-state.sh missing:$W1_missing marker-sites=$w1_marked — an adopted manifest still lacks the keys a scaffolded one has"
fi

# ── W2: EXECUTE the shipped jq filter rather than grepping for the key names.
# W1 is a structural check and this session has already produced two vacuous
# ones, so the write half gets a behavioural assertion too: pull the filter out
# of adopt-state.sh, run it over a bare manifest, and require the result to
# satisfy assert_choosable for the tier it claims.
W2="$(newtmp)"
w2_filter="$(sed -n '/adopt_jq_edit .*manifest.json/,+2p' "$REPO_ROOT/scripts/lib/adopt/adopt-state.sh" | grep -oE "'[.]host = [$]h[^']*'" | head -1 | sed "s/^'//; s/'$//")"
w2_ok=no; w2_note=""
if [ -z "$w2_filter" ]; then
  w2_note="could not extract the shipped jq filter"
else
  for tier in personal organizational; do
    printf '{"host":"github","mode":"%s"}\n' "$tier" > "$W2/in.json"
    jq "$w2_filter" --arg h github --arg m "$tier" --arg d "$tier" --arg p production \
       "$W2/in.json" > "$W2/out.json" 2>/dev/null || { w2_note="jq refused the shipped filter for $tier"; break; }
    mkdir -p "$W2/$tier/.claude"; cp "$W2/out.json" "$W2/$tier/.claude/manifest.json"
    got_dep="$(jq -r '.deployment // "ABSENT"' "$W2/out.json")"
    got_enf="$(jq -r '.enforcement_level // "ABSENT"' "$W2/out.json")"
    [ "$got_dep" = "$tier" ] || { w2_note="$tier: deployment=$got_dep"; break; }
    [ "$got_enf" = "strict" ] || { w2_note="$tier: enforcement_level=$got_enf"; break; }
    if choosable "$W2/$tier"; then r=choosable; else r=refused; fi
    case "$tier:$r" in
      personal:choosable|organizational:refused) w2_ok=yes ;;
      *) w2_note="$tier answered $r"; w2_ok=no; break ;;
    esac
  done
fi
if [ "$w2_ok" = "yes" ]; then
  pass "W2: the SHIPPED jq filter, executed, produces a manifest that assert_choosable reads correctly — personal choosable, organizational refused, enforcement_level seeded strict. W1 proves the keys are named; this proves they land"
else
  fail_ "W2" "${w2_note:-the shipped filter did not produce a manifest the predicate reads correctly}"
fi

echo "=== M — mutation proof ==="

# ── M1: restore the permissive default and A3 must flip back to allowing.
M1="$(newtmp)"; cp -R "$REPO_ROOT/scripts" "$M1/scripts" 2>/dev/null
m1_meta=$(_mutate "$M1/scripts/lib/enforcement-level.sh" '# BL-221-TIER-FAIL-CLOSED' '  deployment=$(jq -r '"'"'.deployment // "personal"'"'"' "$manifest" 2>/dev/null)')
m1_sites="${m1_meta%% *}"; m1_rest="${m1_meta#* }"; m1_changed="${m1_rest%% *}"; m1_parses="${m1_rest##* }"
M1D="$(newtmp)"; mk_manifest "$M1D" '{"poc_mode":"production","enforcement_level":"strict"}'
if choosable "$M1D" "$M1/scripts/lib/enforcement-level.sh"; then m1_res=allowed; else m1_res=refused; fi
if [ "$m1_sites" -eq 1 ] && [ "$m1_parses" -eq 1 ] && [ "$m1_res" = "allowed" ]; then
  pass "M1: with the permissive default restored, an organizational manifest missing its deployment key is CHOOSABLE again — the one-line guard is what stands between a forced-strict project and its own downgrade (sites=$m1_sites changed=$m1_changed parses=$m1_parses)"
else
  fail_ "M1" "sites=$m1_sites (want 1) parses=$m1_parses (want 1) changed=$m1_changed result=$m1_res (want allowed)"
fi

# ── M2: revert the WRITE half but leave its comment standing, and W1 must go
# red. This is the mutant W1 did not have: the explanatory comment above
# `# BL-221-ADOPT-TIER-KEYS` names all three keys in prose, so a whole-file grep
# stayed green against a tree where the jq filter had been stripped back to
# `.host` and `.mode`. The mutant reproduces exactly that state — comment
# intact, behaviour gone — and the assertion below is on W1's OWN predicate, run
# against the mutated file.
#
# awk, not sed: the two lines being replaced ARE the jq filter, which is
# `|`-dense, and CLAUDE.md records three separate occasions on which a
# `|`-delimited sed with a `|`-bearing replacement left the file unchanged while
# reporting success. `m2_rewrites` is asserted for the same reason — "the
# mutation ran" is not "the mutation edited".
M2="$(newtmp)"; cp -R "$REPO_ROOT/scripts" "$M2/scripts" 2>/dev/null
M2F="$M2/scripts/lib/adopt/adopt-state.sh"
m2_tmp="$(mktemp)"
m2_rewrites=$(awk '
  /\.host = \$h \| \.mode = \$m \| \.deployment/ { print "      \x27.host = $h | .mode = $m\x27 \\"; n++; next }
  /\{host: \$h, mode: \$m, remote_url/          { print "      \x27{host: $h, mode: $m, remote_url: \"\"}\x27 \\"; n++; next }
  { print }
  END { print n+0 > "/dev/stderr" }
' "$M2F" 2>&1 >"$m2_tmp" )
mv "$m2_tmp" "$M2F"
m2_rewrites=$(_num "$m2_rewrites")
m2_parses=0; bash -n "$M2F" >/dev/null 2>&1 && m2_parses=1
M2_SRC="$(newtmp)/adopt-state.exec"
awk '/^adopt_write_manifest\(\)/{i=1} i{print} i&&/^}/{exit}' "$M2F" | sed -e 's/[[:space:]]*#.*$//' > "$M2_SRC"
m2_missing=""
m2_n=0
for k in deployment poc_mode enforcement_level; do
  grep -Eq "[.]${k}[[:space:]]*=|${k}:" "$M2_SRC" || { m2_missing="$m2_missing $k"; m2_n=$((m2_n + 1)); }
done
m2_whole_file_hits=$(_num "$(grep -c 'deployment' "$M2F" 2>/dev/null)")
if [ "$m2_rewrites" -eq 2 ] && [ "$m2_parses" -eq 1 ] \
   && [ "$m2_n" -eq 3 ] && [ "$m2_whole_file_hits" -ge 1 ]; then
  pass "M2: with the tier keys stripped from both jq filters and only the comment left, W1's predicate reports ALL THREE missing ($m2_missing) while a whole-file grep for 'deployment' still finds $m2_whole_file_hits hits — comment prose and shell variable names, which is exactly what the original W1 was measuring (rewrites=$m2_rewrites parses=$m2_parses)"
else
  fail_ "M2" "rewrites=$m2_rewrites (want 2) parses=$m2_parses (want 1) missing='$m2_missing' n=$m2_n (want 3 — fewer means a reverted key is still satisfying W1 from somewhere) whole_file_hits=$m2_whole_file_hits (want >=1)"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

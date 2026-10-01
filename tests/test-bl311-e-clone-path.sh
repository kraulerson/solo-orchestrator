#!/usr/bin/env bash
# tests/test-bl311-e-clone-path.sh — BL-311 group E (rows 6 and 7).
#
# THE DEFECTS (brownfield dogfood run 1, 2026-09-27)
#   Row 7: README § Quick Start cloned the framework into whatever directory
#   you were in (`git clone <url>`, no target), docs/adoption.md cloned it to
#   ~/solo-orchestrator, and docs/user-guide.md § 2 cloned bare while its own
#   --sync-framework commands ran ~/solo-orchestrator/scripts/…. The
#   technician could not tell where the framework was meant to live.
#   Row 6: Claude Code's auto mode refused the first framework script run from
#   that clone ([Code from External]) and then refused the agent's attempt to
#   change its own permissions ([Auto-Mode Bypass]). Nothing told the HUMAN to
#   allow the scripts. docs/adoption.md now carries the allow rules, and this
#   suite keeps them matched to the scripts the docs actually run.
#
# THE PREDICATES
#   C1  README.md, docs/adoption.md and docs/user-guide.md each carry the
#       solo-orchestrator clone command; every copy is byte-identical; and it
#       names a target directory (a bare clone lands wherever you happen to be).
#   C2  Inside the ```bash blocks of those three docs, with comments stripped,
#       every path token naming the clone (`solo-orchestrator` as a whole path
#       component) IS the clone target or sits under it: no bare
#       `cd solo-orchestrator`, no `/path/to/solo-orchestrator`, no second home.
#   C3  The allow-rule snippet in docs/adoption.md (the ```json block holding
#       `Bash(bash `) parses with jq; every entry is exactly
#       `Bash(bash <target>/scripts/<script> *)` — so no broad entry such as
#       `Bash(bash *)` can sit in the list —; every named script exists under
#       scripts/; and the set of scripts the rules name EQUALS the set the three
#       docs invoke as `bash <target>/scripts/<script>`. A newly documented
#       script with no rule would be refused in auto mode; a rule for a script
#       no doc runs is stale. Both directions are checked.
#   C4  Every `adoption.md#<anchor>` link in README.md and docs/user-guide.md
#       resolves to a heading of docs/adoption.md (GitHub's slug rule, the one
#       scripts/lint-doc-anchors.sh uses for same-file links — that lint checks
#       only the FILE half of a cross-file link), and both docs link to the
#       heading the snippet sits under.
#
# The clone target is DERIVED from docs/adoption.md's clone command, not pinned
# here: moving the framework is a deliberate edit to every doc and rule at once,
# and C1-C4 stay green through it. What they catch is the docs disagreeing.
#
# DELIBERATELY OUT OF SCOPE
#   • CONTRIBUTING.md's contributor clone. A contributor's checkout location is
#     theirs; no command in the user docs runs a script from it.
#   • Text inside ```text blocks for C2: those are output as printed — the
#     driver's own --help says `/path/to/solo-orchestrator` — not commands to
#     copy. C3 still reads every line, so a documented invocation inside a text
#     block (the test-debt check) still needs its rule.
#
# MUTATION PROOFS — each against a COPY under mktemp -d; the repo is read-only.
#   M1  README's clone command loses its target              -> C1 red
#   M1b all three lose it together (they still agree)        -> C1 red, "no target"
#   M2  adoption.md clones to ~/Code/solo-orchestrator       -> C1 red
#   M3  user-guide.md says `cd solo-orchestrator` again      -> C2 red
#   M4  README runs Scout from /path/to/solo-orchestrator    -> C2 red
#   M5  the snippet loses Scout's rule                       -> C3 red, "no rule"
#   M6  a rule names a script that does not exist            -> C3 red, "no such script"
#   M7  a broad Bash(bash *) entry joins the snippet         -> C3 red, "not a per-script rule"
#   M8  user-guide.md documents a clone script with no rule  -> C3 red, "no rule"
#   M9  a rule for a script no doc runs                      -> C3 red, "stale"
#   M10 README's link to the section mistypes its anchor     -> C4 red
#
# Hermetic: reads three docs and the scripts/ tree, writes only under its own
# mktemp -d. No network, no remote creation.
#
# Self-verify: bash tests/test-bl311-e-clone-path.sh
set -uo pipefail
export LC_ALL=C

SUITE_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SUITE_DIR/.." && pwd)"
README="$REPO_ROOT/README.md"
ADOPT="$REPO_ROOT/docs/adoption.md"
GUIDE="$REPO_ROOT/docs/user-guide.md"
CLONE_URL='https://github.com/kraulerson/solo-orchestrator.git'

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

echo "== tests/test-bl311-e-clone-path.sh =="

for f in "$README" "$ADOPT" "$GUIDE"; do
  if [ ! -f "$f" ]; then
    echo "  [FAIL] fixture — $f not found"
    echo ""
    echo "Results: 0 passed, 1 failed"
    exit 1
  fi
done
if ! command -v jq >/dev/null 2>&1; then
  echo "  [FAIL] fixture — jq is required to parse the allow-rule snippet"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

# --- Extraction -----------------------------------------------------------

# clone_lines <doc> — every line that runs the framework's clone command,
# leading/trailing whitespace stripped. The URL is matched literally and must
# end there or at whitespace, so solo-orchestrator-example-project.git is not it.
clone_lines() {
  SOIF_BL311E_URL="$CLONE_URL" awk '
    BEGIN { p = "git clone " ENVIRON["SOIF_BL311E_URL"] }
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (substr(line, 1, length(p)) == p) {
        rest = substr(line, length(p) + 1)
        if (rest == "" || rest ~ /^[[:space:]]/) print line
      }
    }' "$1"
}

# clone_target <doc> — the target directory of the doc's first clone command.
clone_target() {
  clone_lines "$1" | head -1 | awk '{ print $4 }'
}

# fenced_lines <doc> <info> — "NR<TAB>line" for every line inside a fenced block
# whose opener's info string is exactly <info>. Both fence characters; only the
# same character closes (a ~~~ inside a ```bash block is content).
fenced_lines() {
  SOIF_BL311E_INFO="$2" awk '
    BEGIN { want = ENVIRON["SOIF_BL311E_INFO"] }
    /^[[:space:]]*(```|~~~)/ {
      line = $0
      sub(/^[[:space:]]*/, "", line)
      ch = substr(line, 1, 1)
      if (open) { if (ch == opench) open = 0; next }
      open = 1
      opench = ch
      info = line
      sub(/^(```+|~~~+)[[:space:]]*/, "", info)
      sub(/[[:space:]]+$/, "", info)
      keep = (info == want)
      next
    }
    open && keep { print NR "\t" $0 }
  ' "$1"
}

# snippet_json <adoption-doc> — the one ```json block holding `Bash(bash `.
# Prints it; returns 1 unless there is exactly one.
snippet_json() {
  awk '
    /^[[:space:]]*```/ {
      line = $0
      sub(/^[[:space:]]*/, "", line)
      if (open) {
        open = 0
        if (isjson && buf ~ /"Bash\(bash /) { n++; out = buf }
        next
      }
      open = 1
      info = line
      sub(/^```+[[:space:]]*/, "", info)
      sub(/[[:space:]]+$/, "", info)
      isjson = (info == "json")
      buf = ""
      next
    }
    open { buf = buf $0 "\n" }
    END { if (n != 1) exit 1; printf "%s", out }
  ' "$1"
}

# documented_scripts <target> <doc>... — every `bash <target>/scripts/<x>.sh`
# the docs invoke, as <x>.sh, one per line, unique. An occurrence preceded by
# `(` is a permission rule quoting the command, not an invocation.
documented_scripts() {
  local target="$1"
  shift
  SOIF_BL311E_NEEDLE="bash $target/scripts/" awk '
    BEGIN { needle = ENVIRON["SOIF_BL311E_NEEDLE"] }
    {
      s = $0
      while ((i = index(s, needle)) > 0) {
        before = (i > 1) ? substr(s, i - 1, 1) : ""
        rest = substr(s, i + length(needle))
        if (before != "(" && match(rest, /^[A-Za-z0-9_.\/-]+\.sh/)) {
          print substr(rest, 1, RLENGTH)
        }
        s = rest
      }
    }' "$@" | sort -u
}

# heading_slugs <doc> — the GitHub-derived anchor of every ATX heading outside
# fenced blocks, duplicates suffixed -1, -2 … (scripts/lint-doc-anchors.sh's
# rule). "SNIPPET<TAB>slug" marks the heading the allow-rule snippet sits under.
heading_slugs() {
  awk '
    function slug(h,   s) {
      s = h
      sub(/^#+[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      gsub(/[`*]/, "", s)
      s = tolower(s)
      gsub(/[^a-z0-9 _-]/, "", s)
      gsub(/ /, "-", s)
      return s
    }
    /^[[:space:]]*(```|~~~)/ {
      line = $0
      sub(/^[[:space:]]*/, "", line)
      ch = substr(line, 1, 1)
      if (open) {
        if (ch == opench) {
          open = 0
          if (isjson && buf ~ /"Bash\(bash /) print "SNIPPET\t" last
        }
        next
      }
      open = 1
      opench = ch
      info = line
      sub(/^(```+|~~~+)[[:space:]]*/, "", info)
      sub(/[[:space:]]+$/, "", info)
      isjson = (info == "json")
      buf = ""
      next
    }
    open { buf = buf $0 "\n"; next }
    /^#+[[:space:]]/ {
      s = slug($0)
      seen[s]++
      if (seen[s] > 1) s = s "-" (seen[s] - 1)
      last = s
      print "SLUG\t" s
    }
  ' "$1"
}

# adoption_links <doc> — every anchor the doc links to in adoption.md.
adoption_links() {
  awk '
    {
      s = $0
      while ((i = index(s, "adoption.md#")) > 0) {
        rest = substr(s, i + length("adoption.md#"))
        if (match(rest, /^[A-Za-z0-9_-]+/)) print substr(rest, 1, RLENGTH)
        s = rest
      }
    }' "$1" | sort -u
}

# --- Predicates -------------------------------------------------------------
# Each takes the doc paths, so a mutated copy goes through the identical code.
# Each returns 0 when healthy and prints why when it is not.

# c1_clone_commands_agree <readme> <adoption> <guide>
c1_clone_commands_agree() {
  local f="" n=0 all="$TMP/.c1.all"
  : > "$all"
  for f in "$@"; do
    n=$(clone_lines "$f" | wc -l | tr -d ' ')
    if [ "$n" -lt 1 ]; then
      echo "no clone command in $(basename "$f")"
      return 1
    fi
    clone_lines "$f" >> "$all"
  done
  n=$(sort -u "$all" | wc -l | tr -d ' ')
  if [ "$n" -ne 1 ]; then
    echo "the docs give $n different clone commands:"
    sort -u "$all" | sed 's/^/      /'
    return 1
  fi
  n=$(awk '{ print NF }' "$all" | sort -u | head -1)
  if [ "$n" -lt 4 ]; then
    echo "the clone command names no target directory: $(head -1 "$all")"
    return 1
  fi
  return 0
}

# c2_clone_path_tokens <target> <doc>...
c2_clone_path_tokens() {
  local target="$1" f="" bad="$TMP/.c2.bad"
  shift
  : > "$bad"
  for f in "$@"; do
    fenced_lines "$f" bash | SOIF_BL311E_TARGET="$target" SOIF_BL311E_DOC="$(basename "$f")" awk -F '\t' '
      BEGIN { t = ENVIRON["SOIF_BL311E_TARGET"]; doc = ENVIRON["SOIF_BL311E_DOC"] }
      {
        nr = $1
        line = substr($0, length($1) + 2)
        if (line ~ /^[[:space:]]*#/) next
        sub(/[[:space:]]#.*$/, "", line)
        n = split(line, tok, /[[:space:]]+/)
        for (k = 1; k <= n; k++) {
          w = tok[k]
          gsub(/^["\047`(]+/, "", w)
          gsub(/["\047`);]+$/, "", w)
          if (w ~ /:\/\//) continue
          if (w !~ /(^|\/)solo-orchestrator(\/|$)/) continue
          if (w == t || substr(w, 1, length(t) + 1) == t "/") continue
          print doc ":" nr ": " w
        }
      }' >> "$bad"
  done
  if [ -s "$bad" ]; then
    echo "a command names the clone somewhere other than $target:"
    sed 's/^/      /' "$bad"
    return 1
  fi
  return 0
}

# c3_rules_match_scripts <adoption> <target> <doc>...
c3_rules_match_scripts() {
  local adopt="$1" target="$2" json="$TMP/.c3.json" rules="$TMP/.c3.rules"
  local docs="$TMP/.c3.docs" e="" mid="" prefix="" bad=0 n=0
  shift 2
  if ! snippet_json "$adopt" > "$json"; then
    echo "docs/adoption.md does not hold exactly one json block of Bash(bash …) rules"
    return 1
  fi
  if ! jq -e '.permissions.allow | type == "array" and length > 0' "$json" >/dev/null 2>&1; then
    echo "the snippet is not valid JSON with a non-empty permissions.allow list"
    return 1
  fi
  prefix="Bash(bash $target/scripts/"
  : > "$rules"
  while IFS= read -r e; do
    n=$((n + 1))
    case "$e" in
      "$prefix"*" *)") ;;
      *) echo "not a per-script rule: $e"; bad=1; continue ;;
    esac
    mid="${e#"$prefix"}"
    mid="${mid%" *)"}"
    case "$mid" in
      ''|*[!A-Za-z0-9_./-]*|*..*) echo "not a per-script rule: $e"; bad=1; continue ;;
      *.sh) ;;
      *) echo "not a per-script rule: $e"; bad=1; continue ;;
    esac
    if [ ! -f "$REPO_ROOT/scripts/$mid" ]; then
      echo "no such script: scripts/$mid (rule $e)"
      bad=1
    fi
    echo "$mid" >> "$rules"
  done <<EOF_RULES
$(jq -r '.permissions.allow[]' "$json")
EOF_RULES
  documented_scripts "$target" "$@" > "$docs"
  if [ ! -s "$docs" ]; then
    echo "no doc runs a script as bash $target/scripts/… — nothing to match the rules against"
    return 1
  fi
  sort -u "$rules" -o "$rules"
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    if ! grep -Fxq -- "$e" "$rules"; then
      echo "no rule for scripts/$e, which the docs run from the clone"
      bad=1
    fi
  done < "$docs"
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    if ! grep -Fxq -- "$e" "$docs"; then
      echo "stale rule: scripts/$e is not run by any of the docs"
      bad=1
    fi
  done < "$rules"
  [ "$bad" -eq 0 ]
}

# c4_links_resolve <adoption> <readme> <guide>
c4_links_resolve() {
  local adopt="$1" slugs="$TMP/.c4.slugs" links="$TMP/.c4.links" f="" a="" snip="" bad=0
  shift
  heading_slugs "$adopt" > "$TMP/.c4.raw"
  awk -F '\t' '$1 == "SLUG" { print $2 }' "$TMP/.c4.raw" > "$slugs"
  snip=$(awk -F '\t' '$1 == "SNIPPET" { print $2 }' "$TMP/.c4.raw" | head -1)
  if [ -z "$snip" ]; then
    echo "found no heading above the allow-rule snippet in docs/adoption.md"
    return 1
  fi
  for f in "$@"; do
    adoption_links "$f" > "$links"
    while IFS= read -r a; do
      [ -n "$a" ] || continue
      if ! grep -Fxq -- "$a" "$slugs"; then
        echo "$(basename "$f") links adoption.md#$a, which is no heading there"
        bad=1
      fi
    done < "$links"
    if ! grep -Fxq -- "$snip" "$links"; then
      echo "$(basename "$f") does not link to the allow-rule section (adoption.md#$snip)"
      bad=1
    fi
  done
  [ "$bad" -eq 0 ]
}

# --- The repo's own docs ------------------------------------------------------

TARGET="$(clone_target "$ADOPT")"
if [ -z "$TARGET" ]; then
  echo "  [FAIL] fixture — docs/adoption.md's clone command names no target directory"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

if out=$(c1_clone_commands_agree "$README" "$ADOPT" "$GUIDE"); then
  pass "C1: README, adoption.md and user-guide.md give one clone command, with a target ($(clone_lines "$ADOPT" | head -1))"
else
  fail_ "C1" "$out"
fi

if out=$(c2_clone_path_tokens "$TARGET" "$README" "$ADOPT" "$GUIDE"); then
  pass "C2: every command in their bash blocks names the clone as $TARGET"
else
  fail_ "C2" "$out"
fi

if out=$(c3_rules_match_scripts "$ADOPT" "$TARGET" "$README" "$ADOPT" "$GUIDE"); then
  pass "C3: one rule per script the docs run from the clone ($(documented_scripts "$TARGET" "$README" "$ADOPT" "$GUIDE" | tr '\n' ' '))"
else
  fail_ "C3" "$out"
fi

if out=$(c4_links_resolve "$ADOPT" "$README" "$GUIDE"); then
  pass "C4: README and user-guide.md links into adoption.md resolve, and both link to the allow-rule section"
else
  fail_ "C4" "$out"
fi

# --- Mutation harness -----------------------------------------------------------

# mutate <src> <dst> <old-literal> <new-literal> — replace the FIRST occurrence,
# literally (index/substr: no regex, no `&` rule in any awk), and prove it landed.
mutate() {
  SOIF_BL311E_OLD="$3" SOIF_BL311E_NEW="$4" awk '
    BEGIN { old = ENVIRON["SOIF_BL311E_OLD"]; new = ENVIRON["SOIF_BL311E_NEW"] }
    !done {
      i = index($0, old)
      if (i > 0) { $0 = substr($0, 1, i - 1) new substr($0, i + length(old)); done = 1 }
    }
    { print }
    END { exit(done ? 0 : 1) }' "$1" > "$2" || return 1
  ! cmp -s "$1" "$2" || return 1
  [ -z "$4" ] || grep -Fq -- "$4" "$2"
}

# drop_line <src> <dst> <literal> — delete the first line containing it.
drop_line() {
  SOIF_BL311E_OLD="$3" awk '
    BEGIN { old = ENVIRON["SOIF_BL311E_OLD"] }
    !done && index($0, old) > 0 { done = 1; next }
    { print }
    END { exit(done ? 0 : 1) }' "$1" > "$2" || return 1
  ! cmp -s "$1" "$2"
}

# expect_red <id> <what> <expected-reason-or-empty> <predicate> <args>...
expect_red() {
  local id="$1" what="$2" want="$3" out=""
  shift 3
  if out=$("$@"); then
    fail_ "$id" "mutant survived: $what — the predicate still passes"
    return
  fi
  if [ -n "$want" ] && ! printf '%s\n' "$out" | grep -Fq -- "$want"; then
    fail_ "$id" "red for the wrong reason: wanted '$want', got: $out"
    return
  fi
  pass "$id: $what -> red${want:+ ($want)}"
}

M="$TMP/m"
mkdir -p "$M"
RULE_SCOUT="\"Bash(bash $TARGET/scripts/scout.sh *)\","
RULE_DEBT="Bash(bash $TARGET/scripts/lib/adopt/adopt-test-debt.sh *)"

if mutate "$README" "$M/README.m1.md" "solo-orchestrator.git $TARGET" "solo-orchestrator.git"; then
  expect_red M1 "README clones with no target" "different clone commands" c1_clone_commands_agree "$M/README.m1.md" "$ADOPT" "$GUIDE"
else
  fail_ M1 "mutation did not land in README.md"
fi

# All three bare at once agree with each other — the target arm has to catch it.
if mutate "$ADOPT" "$M/adoption.m1b.md" "solo-orchestrator.git $TARGET" "solo-orchestrator.git" \
  && mutate "$GUIDE" "$M/user-guide.m1b.md" "solo-orchestrator.git $TARGET" "solo-orchestrator.git"; then
  expect_red M1b "all three docs clone with no target" "names no target directory" c1_clone_commands_agree "$M/README.m1.md" "$M/adoption.m1b.md" "$M/user-guide.m1b.md"
else
  fail_ M1b "mutation did not land in docs/adoption.md and docs/user-guide.md"
fi

if mutate "$ADOPT" "$M/adoption.m2.md" "solo-orchestrator.git $TARGET" "solo-orchestrator.git ~/Code/solo-orchestrator"; then
  expect_red M2 "adoption.md clones to ~/Code/solo-orchestrator" "different clone commands" c1_clone_commands_agree "$README" "$M/adoption.m2.md" "$GUIDE"
else
  fail_ M2 "mutation did not land in docs/adoption.md"
fi

if mutate "$GUIDE" "$M/user-guide.m3.md" "cd $TARGET" "cd solo-orchestrator"; then
  expect_red M3 "user-guide.md says cd solo-orchestrator" "user-guide.m3.md:" c2_clone_path_tokens "$TARGET" "$README" "$ADOPT" "$M/user-guide.m3.md"
else
  fail_ M3 "mutation did not land in docs/user-guide.md"
fi

if mutate "$README" "$M/README.m4.md" "bash $TARGET/scripts/scout.sh" "bash /path/to/solo-orchestrator/scripts/scout.sh"; then
  expect_red M4 "README runs Scout from /path/to/solo-orchestrator" "/path/to/solo-orchestrator/scripts/scout.sh" c2_clone_path_tokens "$TARGET" "$M/README.m4.md" "$ADOPT" "$GUIDE"
else
  fail_ M4 "mutation did not land in README.md"
fi

if drop_line "$ADOPT" "$M/adoption.m5.md" "$RULE_SCOUT"; then
  expect_red M5 "the snippet loses Scout's rule" "no rule for scripts/scout.sh" c3_rules_match_scripts "$M/adoption.m5.md" "$TARGET" "$README" "$M/adoption.m5.md" "$GUIDE"
else
  fail_ M5 "mutation did not land in docs/adoption.md"
fi

if mutate "$ADOPT" "$M/adoption.m6.md" "$RULE_DEBT" "Bash(bash $TARGET/scripts/lib/adopt/adopt-debt.sh *)"; then
  expect_red M6 "a rule names a script that does not exist" "no such script: scripts/lib/adopt/adopt-debt.sh" c3_rules_match_scripts "$M/adoption.m6.md" "$TARGET" "$README" "$M/adoption.m6.md" "$GUIDE"
else
  fail_ M6 "mutation did not land in docs/adoption.md"
fi

if mutate "$ADOPT" "$M/adoption.m7.md" "$RULE_SCOUT" "\"Bash(bash *)\", $RULE_SCOUT"; then
  expect_red M7 "a broad Bash(bash *) entry joins the snippet" "not a per-script rule: Bash(bash *)" c3_rules_match_scripts "$M/adoption.m7.md" "$TARGET" "$README" "$M/adoption.m7.md" "$GUIDE"
else
  fail_ M7 "mutation did not land in docs/adoption.md"
fi

if mutate "$GUIDE" "$M/user-guide.m8.md" "bash $TARGET/scripts/upgrade-project.sh --sync-framework --dry-run" "bash $TARGET/scripts/check-updates.sh --dry-run"; then
  expect_red M8 "user-guide.md runs a clone script the snippet has no rule for" "no rule for scripts/check-updates.sh" c3_rules_match_scripts "$ADOPT" "$TARGET" "$README" "$ADOPT" "$M/user-guide.m8.md"
else
  fail_ M8 "mutation did not land in docs/user-guide.md"
fi

if mutate "$ADOPT" "$M/adoption.m9.md" "$RULE_SCOUT" "$RULE_SCOUT \"Bash(bash $TARGET/scripts/check-updates.sh *)\","; then
  expect_red M9 "a rule for a script no doc runs" "stale rule: scripts/check-updates.sh" c3_rules_match_scripts "$M/adoption.m9.md" "$TARGET" "$README" "$M/adoption.m9.md" "$GUIDE"
else
  fail_ M9 "mutation did not land in docs/adoption.md"
fi

SNIP_SLUG="$(heading_slugs "$ADOPT" | awk -F '\t' '$1 == "SNIPPET" { print $2 }' | head -1)"
if [ -n "$SNIP_SLUG" ] && mutate "$README" "$M/README.m10.md" "adoption.md#$SNIP_SLUG" "adoption.md#${SNIP_SLUG}x"; then
  expect_red M10 "README's link to the section mistypes its anchor" "which is no heading there" c4_links_resolve "$ADOPT" "$M/README.m10.md" "$GUIDE"
else
  fail_ M10 "mutation did not land in README.md (snippet heading slug: '${SNIP_SLUG}')"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

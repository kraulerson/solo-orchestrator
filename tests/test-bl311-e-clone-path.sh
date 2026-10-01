#!/usr/bin/env bash
# tests/test-bl311-e-clone-path.sh — BL-311 group E (rows 6 and 7).
#
# THE DEFECTS (brownfield dogfood run 1, 2026-09-27)
#   Row 7: README § Quick Start cloned the framework into whatever directory
#   you were in (`git clone <url>`, no target), docs/adoption.md cloned it to
#   ~/solo-orchestrator, and docs/user-guide.md § 2 cloned bare while its own
#   --sync-framework commands ran ~/solo-orchestrator/scripts/…. The
#   technician could not tell where the framework was meant to live.
#   Row 6: a framework script run from the clone can be refused by Claude
#   Code's auto mode ([Code from External]) — it was in the 2026-09-27 run,
#   where the agent had cloned the framework itself in that same session — and
#   the agent's attempt to change its own permissions was refused too
#   ([Auto-Mode Bypass]). Nothing told the HUMAN what to do.
#   docs/adoption.md step 2 now carries ONE autoMode.environment entry for the
#   user's settings that names the clone and its GitHub repository as trusted
#   — not Bash allow rules, which would let Claude run the framework's scripts
#   with any arguments unseen by the classifier, machine-wide — plus a fallback
#   for when Claude is still refused.
#
# THE PREDICATES
#   C1  README.md, docs/adoption.md and docs/user-guide.md each carry the
#       solo-orchestrator clone command; every copy is byte-identical; and it
#       names a target directory (a bare clone lands wherever you happen to be).
#   C2  Inside the ```bash blocks of those three docs, with comments stripped,
#       every path token naming the clone (`solo-orchestrator` as a whole path
#       component) IS the clone target or sits under it: no bare
#       `cd solo-orchestrator`, no `/path/to/solo-orchestrator`, no second home.
#   C3  docs/adoption.md holds exactly one ```json block naming "autoMode",
#       it parses, and it is EXACTLY
#         {"autoMode":{"environment":["$defaults", <one string>]}}
#       — pinned with jq -e, so a `permissions` block (an allow list, a
#       `defaultMode` of bypassPermissions), an `autoMode.allow`, a missing
#       "$defaults" or a second entry is red. The one string names the clone's
#       GitHub repository (from the clone URL) and the clone path, and every
#       other solo-orchestrator path in it is that same path: the C1 target.
#   C4  Every `adoption.md#<anchor>` link in README.md and docs/user-guide.md
#       resolves to a heading of docs/adoption.md (GitHub's slug rule, the one
#       scripts/lint-doc-anchors.sh uses for same-file links — that lint checks
#       only the FILE half of a cross-file link), and both docs link to the
#       heading the snippet sits under.
#   C5  The section holding the snippet carries the fallback for when Claude is
#       still refused: run the command yourself — in your own terminal or after
#       `!` — or leave auto mode with `Shift+Tab`.
#   C6  Every script a user runs from the clone, in all three docs — any fenced
#       block or prose — is spelled `bash <target>/scripts/…` or with the
#       documented `"$(jq -r .source_dir .claude/orchestrator-source.json)` form:
#         • no `cd <clone>` followed, in the same fenced block, by a relative
#           `bash scripts/…`, `bash ./scripts/…` or `./scripts/…`;
#         • no `bash <other>/scripts/x.sh` whose <other> is neither of those
#           two (nor `.`, the project's own copy);
#         • no `/path/to/solo-orchestrator` and no `<framework>` placeholder —
#           EXCEPT a line inside a ```text block that is, trimmed, exactly a
#           line of a script under scripts/: the docs quoting what a script
#           prints (adopt-project.sh's --help). That exemption ends by itself
#           when the script's text changes, which forces the doc to follow.
#
# The clone target is DERIVED from docs/adoption.md's clone command, not pinned
# here: moving the framework is a deliberate edit to every doc and the settings
# entry at once, and C1-C6 stay green through it. What they catch is the docs
# disagreeing.
#
# DELIBERATELY OUT OF SCOPE
#   • CONTRIBUTING.md's contributor clone. A contributor's checkout location is
#     theirs; no command in the user docs runs a script from it.
#   • Text inside ```text blocks for C2: those are output as printed — the
#     driver's own --help says `/path/to/solo-orchestrator` — not commands to
#     copy. C6 still reads every line, and holds a quoted line to the script it
#     quotes.
#   • Whether the entry clears the [Code from External] refusal. That is a
#     property of Claude Code's classifier, measured by the clean dogfood
#     rerun, not by a file check.
#   • A script named bare in prose (`adopt-project.sh --finish`) with no
#     `bash` in front: too common in prose to tell from a mention.
#
# MUTATION PROOFS — each against a COPY under mktemp -d; the repo is read-only.
#   M1  README's clone command loses its target              -> C1 red
#   M1b all three lose it together (they still agree)        -> C1 red, "no target"
#   M2  adoption.md clones to ~/Code/solo-orchestrator       -> C1 red
#   M3  user-guide.md says `cd solo-orchestrator` again      -> C2 red
#   M4  README runs Scout from /path/to/solo-orchestrator    -> C2 red
#   M5  the snippet gains permissions.defaultMode bypassPermissions -> C3 red
#   M6  the snippet gains a permissions.allow rule           -> C3 red
#   M7  the snippet gains an autoMode.allow list             -> C3 red
#   M8  the snippet loses "$defaults"                        -> C3 red
#   M9  the snippet gains a second environment entry         -> C3 red
#   M10 the entry names ~/Code/solo-orchestrator             -> C3 red, path
#   M11 the entry no longer names the GitHub repository      -> C3 red
#   M12 README's link to the section mistypes its anchor     -> C4 red
#   M13 the fallback paragraph is removed                    -> C5 red
#   M14 README's Scout block is back to `cd` + relative      -> C6 red
#   M15 adoption.md's test-debt check says `<framework>`     -> C6 red
#   M16 the --help quote no longer matches what the driver prints -> C6 red
#   M17 user-guide.md spells the clone "$HOME/solo-orchestrator" -> C6 red
#
# Hermetic: reads three docs and the scripts/ tree, writes only under its own
# mktemp -d. No network, no remote creation, no `claude`.
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
# The clone's GitHub repository as the entry names it: no scheme, no .git.
REMOTE="${CLONE_URL#https://}"
REMOTE="${REMOTE%.git}"
# The documented way a project names its clone without knowing where it is.
SOURCE_DIR_FORM='"$(jq -r .source_dir .claude/orchestrator-source.json)'
TAB="$(printf '\t')"

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
  echo "  [FAIL] fixture — jq is required to parse the settings snippet"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

# Every line of every script under scripts/, trimmed — what a script can print.
PRINTED="$TMP/.printed"
find "$REPO_ROOT/scripts" -type f -name '*.sh' -exec cat {} + \
  | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' > "$PRINTED"
if [ ! -s "$PRINTED" ]; then
  echo "  [FAIL] fixture — read no script text under $REPO_ROOT/scripts"
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

# snippet_json <adoption-doc> — the one ```json block naming "autoMode".
# Prints it; returns 1 unless there is exactly one.
snippet_json() {
  awk '
    /^[[:space:]]*```/ {
      line = $0
      sub(/^[[:space:]]*/, "", line)
      if (open) {
        open = 0
        if (isjson && buf ~ /"autoMode"/) { n++; out = buf }
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

# heading_slugs <doc> — the GitHub-derived anchor of every ATX heading outside
# fenced blocks, duplicates suffixed -1, -2 … (scripts/lint-doc-anchors.sh's
# rule). "SLUG<TAB>slug" per heading; "SNIPPET<TAB>slug<TAB>NR<TAB>level" for
# the heading the settings snippet sits under.
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
          if (isjson && buf ~ /"autoMode"/) print "SNIPPET\t" last "\t" lastnr "\t" lastlvl
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
      lastnr = NR
      match($0, /^#+/)
      lastlvl = RLENGTH
      print "SLUG\t" s
    }
  ' "$1"
}

# snippet_section <adoption-doc> — the lines of the section holding the
# settings snippet: from its heading to the next heading (outside fences) of
# the same or a higher level.
snippet_section() {
  local row="" nr="" lvl=""
  row=$(heading_slugs "$1" | awk -F '\t' '$1 == "SNIPPET" { print $3 "\t" $4; exit }')
  [ -n "$row" ] || return 1
  nr="$(printf '%s\n' "$row" | cut -f1)"
  lvl="$(printf '%s\n' "$row" | cut -f2)"
  awk -v start="$nr" -v lvl="$lvl" '
    NR < start { next }
    /^[[:space:]]*(```|~~~)/ { fence = !fence; print; next }
    NR > start && !fence && /^#+[[:space:]]/ {
      match($0, /^#+/)
      if (RLENGTH <= lvl) exit
    }
    { print }
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

# c3_snippet_shape <adoption> <target>
c3_snippet_shape() {
  local adopt="$1" target="$2" json="$TMP/.c3.json" entry="" paths="$TMP/.c3.paths"
  if ! snippet_json "$adopt" > "$json"; then
    echo "docs/adoption.md does not hold exactly one json block naming \"autoMode\""
    return 1
  fi
  if ! jq -e . "$json" >/dev/null 2>&1; then
    echo "the snippet is not valid JSON"
    return 1
  fi
  # The whole shape, so anything added beside the one entry is red.
  if ! jq -e '
      type == "object" and keys == ["autoMode"]
      and (.autoMode | type == "object" and keys == ["environment"])
      and (.autoMode.environment | type == "array" and length == 2)
      and .autoMode.environment[0] == "$defaults"
      and (.autoMode.environment[1] | type == "string")
    ' "$json" >/dev/null 2>&1; then
    echo "the snippet is not exactly {\"autoMode\":{\"environment\":[\"\$defaults\", <one entry>]}}: $(jq -c . "$json" 2>/dev/null | cut -c1-200)"
    return 1
  fi
  entry=$(jq -r '.autoMode.environment[1]' "$json")
  case "$entry" in
    *"$REMOTE"*) ;;
    *) echo "the entry does not name the clone's repository $REMOTE: $entry"; return 1 ;;
  esac
  # Every solo-orchestrator path in the entry, the repository set aside.
  printf '%s\n' "$entry" | awk -v remote="$REMOTE" '
    {
      n = split($0, tok, /[[:space:]]+/)
      for (k = 1; k <= n; k++) {
        w = tok[k]
        gsub(/^["\047`(]+/, "", w)
        gsub(/["\047`),;:.]+$/, "", w)
        if (w ~ /:\/\// || index(w, remote) > 0) continue
        if (w ~ /(^|\/)solo-orchestrator(\/|$)/) print w
      }
    }' > "$paths"
  if ! grep -Fxq -- "$target" "$paths"; then
    echo "the entry does not name the clone at $target: $entry"
    return 1
  fi
  if grep -Fxv -- "$target" "$paths" | grep -q .; then
    echo "the entry names the clone somewhere other than $target: $(grep -Fxv -- "$target" "$paths" | tr '\n' ' ')"
    return 1
  fi
  return 0
}

# c4_links_resolve <adoption> <readme> <guide>
c4_links_resolve() {
  local adopt="$1" slugs="$TMP/.c4.slugs" links="$TMP/.c4.links" f="" a="" snip="" bad=0
  shift
  heading_slugs "$adopt" > "$TMP/.c4.raw"
  awk -F '\t' '$1 == "SLUG" { print $2 }' "$TMP/.c4.raw" > "$slugs"
  snip=$(awk -F '\t' '$1 == "SNIPPET" { print $2 }' "$TMP/.c4.raw" | head -1)
  if [ -z "$snip" ]; then
    echo "found no heading above the settings snippet in docs/adoption.md"
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
      echo "$(basename "$f") does not link to the settings step (adoption.md#$snip)"
      bad=1
    fi
  done
  [ "$bad" -eq 0 ]
}

# c5_fallback <adoption>
c5_fallback() {
  local sec="$TMP/.c5.sec" want="" bad=0
  if ! snippet_section "$1" > "$sec" || [ ! -s "$sec" ]; then
    echo "found no section holding the settings snippet in docs/adoption.md"
    return 1
  fi
  for want in 'run the command yourself' 'your own terminal' '`!`' '`Shift+Tab`'; do
    if ! grep -Fq -- "$want" "$sec"; then
      echo "the settings step has no fallback text '$want'"
      bad=1
    fi
  done
  [ "$bad" -eq 0 ]
}

# c6_clone_invocations <target> <doc>... — prints what it exempted on success.
c6_clone_invocations() {
  local target="$1" f="" bad="$TMP/.c6.bad" cand="$TMP/.c6.cand" ex="$TMP/.c6.ex"
  local doc="" where="" intext="" line=""
  shift
  : > "$bad"
  : > "$ex"
  for f in "$@"; do
    doc="$(basename "$f")"
    SOIF_BL311E_TARGET="$target" SOIF_BL311E_DOC="$doc" SOIF_BL311E_SRC="$SOURCE_DIR_FORM" awk '
      BEGIN {
        t = ENVIRON["SOIF_BL311E_TARGET"]; doc = ENVIRON["SOIF_BL311E_DOC"]
        src = ENVIRON["SOIF_BL311E_SRC"]
      }
      function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
      # cd_arg_is_clone(a) — a `cd` argument naming a solo-orchestrator clone.
      function cd_arg_is_clone(a) {
        gsub(/^["\047]+/, "", a); gsub(/["\047;]+$/, "", a); sub(/\/$/, "", a)
        return (a ~ /(^|\/)solo-orchestrator$/)
      }
      /^[[:space:]]*(```|~~~)/ {
        l = trim($0)
        ch = substr(l, 1, 1)
        if (open) { if (ch == opench) { open = 0; cdclone = 0 }; next }
        open = 1; opench = ch; cdclone = 0
        info = l
        sub(/^(```+|~~~+)[[:space:]]*/, "", info)
        intext = (info == "text")
        next
      }
      {
        line = $0
        # Placeholders: a doc instruction may not use them; a quoted line of a
        # script inside a text block is checked against scripts/ by the caller.
        if (index(line, "/path/to/solo-orchestrator") > 0 || index(line, "<framework>") > 0) {
          print "CAND\t" doc ":" NR "\t" ((open && intext) ? 1 : 0) "\t" trim(line)
        }
        # Prefixed invocations: the documented source_dir form is set aside.
        s = line
        while ((i = index(s, src)) > 0) s = substr(s, 1, i - 1) "@SRC@" substr(s, i + length(src))
        while (match(s, /bash[[:space:]]+[^[:space:]]+\/scripts\/[A-Za-z0-9_.\/-]+\.sh/)) {
          m = substr(s, RSTART, RLENGTH)
          s = substr(s, RSTART + RLENGTH)
          p = m
          sub(/^bash[[:space:]]+/, "", p)
          sub(/\/scripts\/[A-Za-z0-9_.\/-]+\.sh$/, "", p)
          gsub(/^["\047`]+/, "", p)
          if (p == t || p == "@SRC@" || p == ".") continue
          if (index(line, "/path/to/solo-orchestrator") > 0 || index(line, "<framework>") > 0) continue
          print "BAD\t" doc ":" NR ": runs a clone script as " m
        }
        if (!open) next
        # cd into the clone, then a relative script, in the same block.
        c = line
        sub(/^[[:space:]]*#.*$/, "", c)
        sub(/[[:space:]]#.*$/, "", c)
        n = split(c, part, /(&&|;|\|\|)/)
        for (k = 1; k <= n; k++) {
          seg = trim(part[k])
          if (seg ~ /^cd([[:space:]]|$)/) {
            arg = seg
            sub(/^cd[[:space:]]*/, "", arg)
            cdclone = cd_arg_is_clone(arg) ? 1 : 0
            continue
          }
          if (cdclone && seg ~ /^(bash[[:space:]]+)?(\.\/)?scripts\/[A-Za-z0-9_.\/-]+\.sh/) {
            print "BAD\t" doc ":" NR ": runs " seg " relative to a cd into the clone"
          }
        }
      }
    ' "$f" > "$cand"
    awk -F '\t' '$1 == "BAD" { print $2 }' "$cand" >> "$bad"
    while IFS="$TAB" read -r where intext line; do
      [ -n "$where" ] || continue
      if [ "$intext" = 1 ] && grep -Fxq -- "$line" "$PRINTED"; then
        echo "$where" >> "$ex"
      else
        echo "$where: a placeholder for the clone: $line" >> "$bad"
      fi
    done <<EOF_CAND
$(awk -F '\t' '$1 == "CAND" { print $2 "\t" $3 "\t" $4 }' "$cand")
EOF_CAND
  done
  if [ -s "$bad" ]; then
    echo "a clone script is not spelled bash $target/scripts/… (or the documented source_dir form):"
    sed 's/^/      /' "$bad"
    return 1
  fi
  if [ -s "$ex" ]; then
    echo "quoted script output kept: $(tr '\n' ' ' < "$ex" | sed 's/ $//')"
  fi
  return 0
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

if out=$(c3_snippet_shape "$ADOPT" "$TARGET"); then
  pass "C3: the settings snippet is exactly {autoMode:{environment:[\$defaults, one entry]}}, naming $REMOTE and $TARGET"
else
  fail_ "C3" "$out"
fi

if out=$(c4_links_resolve "$ADOPT" "$README" "$GUIDE"); then
  pass "C4: README and user-guide.md links into adoption.md resolve, and both link to the settings step"
else
  fail_ "C4" "$out"
fi

if out=$(c5_fallback "$ADOPT"); then
  pass "C5: the settings step says what to do when Claude is still refused (your own terminal, !, Shift+Tab)"
else
  fail_ "C5" "$out"
fi

if out=$(c6_clone_invocations "$TARGET" "$README" "$ADOPT" "$GUIDE"); then
  pass "C6: every clone script in the three docs is run as bash $TARGET/scripts/… or the source_dir form${out:+ ($out)}"
else
  fail_ "C6" "$out"
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

# drop_para <src> <dst> <literal> — delete the paragraph whose first line
# contains it: that line through the next blank line.
drop_para() {
  SOIF_BL311E_OLD="$3" awk '
    BEGIN { old = ENVIRON["SOIF_BL311E_OLD"] }
    !done && !on && index($0, old) > 0 { on = 1; done = 1; next }
    on && /^[[:space:]]*$/ { on = 0; print; next }
    on { next }
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
ENTRY=""
if snippet_json "$ADOPT" > "$TMP/.entry.json" 2>/dev/null; then
  ENTRY="$(jq -r '.autoMode.environment[1] // empty' "$TMP/.entry.json" 2>/dev/null)"
fi
NOT_EXACT='is not exactly {"autoMode"'

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

if mutate "$ADOPT" "$M/adoption.m5.md" '"autoMode": {' '"permissions": { "defaultMode": "bypassPermissions" }, "autoMode": {'; then
  expect_red M5 "the snippet gains permissions.defaultMode bypassPermissions" "$NOT_EXACT" c3_snippet_shape "$M/adoption.m5.md" "$TARGET"
else
  fail_ M5 "mutation did not land in docs/adoption.md"
fi

if mutate "$ADOPT" "$M/adoption.m6.md" '"autoMode": {' "\"permissions\": { \"allow\": [\"Bash(bash $TARGET/scripts/scout.sh *)\"] }, \"autoMode\": {"; then
  expect_red M6 "the snippet gains a permissions.allow rule" "$NOT_EXACT" c3_snippet_shape "$M/adoption.m6.md" "$TARGET"
else
  fail_ M6 "mutation did not land in docs/adoption.md"
fi

if mutate "$ADOPT" "$M/adoption.m7.md" '"autoMode": {' '"autoMode": { "allow": ["$defaults", "Running any script from the clone is allowed"],'; then
  expect_red M7 "the snippet gains an autoMode.allow list" "$NOT_EXACT" c3_snippet_shape "$M/adoption.m7.md" "$TARGET"
else
  fail_ M7 "mutation did not land in docs/adoption.md"
fi

if mutate "$ADOPT" "$M/adoption.m8.md" '"$defaults",' ''; then
  expect_red M8 "the snippet loses \"\$defaults\"" "$NOT_EXACT" c3_snippet_shape "$M/adoption.m8.md" "$TARGET"
else
  fail_ M8 "mutation did not land in docs/adoption.md"
fi

if mutate "$ADOPT" "$M/adoption.m9.md" '"$defaults",' '"$defaults", "Trusted internal domains: *.example.com",'; then
  expect_red M9 "the snippet gains a second environment entry" "$NOT_EXACT" c3_snippet_shape "$M/adoption.m9.md" "$TARGET"
else
  fail_ M9 "mutation did not land in docs/adoption.md"
fi

# The entry's own text, rebuilt by splitting on the literal (no ${x/y/z}).
if [ -n "$ENTRY" ] && case "$ENTRY" in *"$TARGET"*) true ;; *) false ;; esac \
  && mutate "$ADOPT" "$M/adoption.m10.md" "$ENTRY" "${ENTRY%%"$TARGET"*}~/Code/solo-orchestrator${ENTRY#*"$TARGET"}"; then
  expect_red M10 "the entry names ~/Code/solo-orchestrator" "~/Code/solo-orchestrator" c3_snippet_shape "$M/adoption.m10.md" "$TARGET"
else
  fail_ M10 "mutation did not land in docs/adoption.md (entry: '$ENTRY')"
fi

if [ -n "$ENTRY" ] && case "$ENTRY" in *"$REMOTE"*) true ;; *) false ;; esac \
  && mutate "$ADOPT" "$M/adoption.m11.md" "$ENTRY" "${ENTRY%%"$REMOTE"*}the framework's repository${ENTRY#*"$REMOTE"}"; then
  expect_red M11 "the entry no longer names the GitHub repository" "does not name the clone's repository" c3_snippet_shape "$M/adoption.m11.md" "$TARGET"
else
  fail_ M11 "mutation did not land in docs/adoption.md (entry: '$ENTRY')"
fi

SNIP_SLUG="$(heading_slugs "$ADOPT" | awk -F '\t' '$1 == "SNIPPET" { print $2 }' | head -1)"
if [ -n "$SNIP_SLUG" ] && mutate "$README" "$M/README.m12.md" "adoption.md#$SNIP_SLUG" "adoption.md#${SNIP_SLUG}x"; then
  expect_red M12 "README's link to the section mistypes its anchor" "which is no heading there" c4_links_resolve "$ADOPT" "$M/README.m12.md" "$GUIDE"
else
  fail_ M12 "mutation did not land in README.md (snippet heading slug: '${SNIP_SLUG}')"
fi

if drop_para "$ADOPT" "$M/adoption.m13.md" "**If Claude is still refused"; then
  expect_red M13 "the fallback paragraph is removed" "has no fallback text" c5_fallback "$M/adoption.m13.md"
else
  fail_ M13 "mutation did not land in docs/adoption.md"
fi

if mutate "$README" "$M/README.m14.md" "bash $TARGET/scripts/scout.sh --root" "cd $TARGET
bash scripts/scout.sh --root"; then
  expect_red M14 "README's Scout block is back to cd + relative" "relative to a cd into the clone" c6_clone_invocations "$TARGET" "$M/README.m14.md" "$ADOPT" "$GUIDE"
else
  fail_ M14 "mutation did not land in README.md"
fi

if mutate "$ADOPT" "$M/adoption.m15.md" "bash $TARGET/scripts/lib/adopt/adopt-test-debt.sh --check --root ." "bash <framework>/scripts/lib/adopt/adopt-test-debt.sh --check --root ."; then
  expect_red M15 "adoption.md's test-debt check says <framework>" "a placeholder for the clone" c6_clone_invocations "$TARGET" "$README" "$M/adoption.m15.md" "$GUIDE"
else
  fail_ M15 "mutation did not land in docs/adoption.md"
fi

if mutate "$ADOPT" "$M/adoption.m16.md" "bash /path/to/solo-orchestrator/scripts/adopt-project.sh [options]" "bash /path/to/solo-orchestrator/scripts/adopt-project.sh --scan-report FILE"; then
  expect_red M16 "the --help quote no longer matches what the driver prints" "a placeholder for the clone" c6_clone_invocations "$TARGET" "$README" "$M/adoption.m16.md" "$GUIDE"
else
  fail_ M16 "mutation did not land in docs/adoption.md"
fi

if mutate "$GUIDE" "$M/user-guide.m17.md" "bash $TARGET/scripts/upgrade-project.sh --sync-framework --dry-run" "bash \"\$HOME/solo-orchestrator/scripts/upgrade-project.sh\" --sync-framework --dry-run"; then
  expect_red M17 "user-guide.md spells the clone \"\$HOME/solo-orchestrator\"" "runs a clone script as bash \"\$HOME/solo-orchestrator/scripts/upgrade-project.sh" c6_clone_invocations "$TARGET" "$README" "$ADOPT" "$M/user-guide.m17.md"
else
  fail_ M17 "mutation did not land in docs/user-guide.md"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

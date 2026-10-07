#!/usr/bin/env bash
# scripts/lib/scout/scout-ignore.sh — `## BL-322:` S3: would this project's own
# ignore rules stop an adoption? The ignore test adoption runs before it writes
# anything, in ONE place, with two callers:
#
#   Scout (scout_ignore_scan, from scripts/scout.sh) asks it over the files an
#   adoption writes whatever the operator answers, and reports a block before
#   anyone has answered a question;
#   the adoption driver's pre-write check (`adopt_prewrite_preflight`,
#   `# BL-225-PREWRITE-REFUSE`) sources this file and asks it over the paths its
#   rehearsal actually wrote.
#
# Dogfood run 3, finding 4: k-pdf's `.gitignore` line 20 is `lib/`, a standard
# Python template line, and it refuses `scripts/lib/`. Adoption stopped on it
# after every question had been answered; Scout, run first to say what adoption
# would meet, had said nothing, because nothing in it asked.
#
# M5: Scout's rules bind this file. It sources nothing, names no core lib, and
# needs git, awk, sed and sort, not jq. The adoption driver may source a Scout
# file (module to module; `adopt-tools.sh` sources three); core may not.
#
# ─────────────────────────────────────────────────────────────────────────────
# WHAT IS SHARED AND WHAT IS NOT
#
# SHARED: the decision (`scout_ignore_refused`) and the naming of each rule
# (`scout_ignore_rule_rows`, `scout_ignore_rules_explain`). They moved here from
# scripts/lib/adopt/adopt-state.sh unchanged except for the sort below, so the
# answer and its words are the same code in both places.
#
# NOT SHARED, AND WHY: the set of paths. Adoption's is the ledger of a rehearsal
# that runs its real write phase on a copy of the tree (`# BL-225-PREWRITE-CALL`)
# — it needs the operator's answers and the adoption driver, and Scout has
# neither. So `scout_adoption_write_set` derives the set from the framework clone
# Scout runs from, by extraction (docs/module-contract.md M5: copy the predicate,
# not the dependency), and tests/test-bl322-s3-ignore-preflight.sh holds it
# EQUAL to a real rehearsal's ledger (P1, P2) and holds the two answers equal on
# the same tree (A1-A6). A writer added to adoption and not here reds P1.
#
# WHAT SCOUT DOES NOT PREDICT: the archive (a folder of copies named for each
# run), `.claude/test-command` (written only when the operator keeps the scan's
# command) and the Development Guardrails' own files (installed only when the
# operator chooses to). Adoption checks those itself before it writes anything,
# and the report says so. APPROVAL_LOG.md and `.claude/bypass-audit.json` never
# stop an adoption: it stages them only when git will (`_adopt_record_if_stageable`).
#
# bash 3.2 safe; every local is assigned where it is declared.

# scout_ignore_refused ROOT — stdin: the paths a run will write, one per line.
# stdout: `R<TAB>path<TAB>asked` for each path the ignore rules refuse, where
# `asked` is the path the decision asked git about; returns 0. If git cannot
# answer for a path, `F<TAB>path<TAB>rc` and returns 2 (fail closed).
#
# THE ORACLE, AND WHY IT IS TWO QUESTIONS AND NOT ONE. `git add` refuses an
# ignored path — but for a path already TRACKED it refuses only when an
# ANCESTOR DIRECTORY is ignored, not when a file or glob rule covers it.
# Measured across four rule shapes on a tracked path (`git add` rc):
#     .claude/   -> 1     .claude/*  -> 0     *.json -> 0     exact path -> 0
# A first cut asked `check-ignore --no-index` for every path, which says
# IGNORED in all four and so REFUSED THREE PROJECTS THAT WORK TODAY — any
# adoptee that tracks a file the adoption rewrites and has a non-directory
# rule covering it. Two measurements of the same thing had been generalised
# from one rule shape each, in opposite directions; twelve shapes settled it.
# `--no-index` stays for the untracked half: without it git reports nothing
# for a tracked path, the index-aware false-clean that defeated the first fix
# of `# BL-225-STAGE-PREFLIGHT`.
#
# FAIL CLOSED. `check-ignore` exits 128 on a pathspec beyond a symbolic link,
# and treating that as "not ignored" would be a fail-OPEN guard — the shape
# `## BL-225:` exists to remove. Anything but 0 or 1 stops the answer.
#
# ONE PATH FEEDS BOTH QUESTIONS (`## BL-311:` row 5). `asked` is what the
# decision asks about — the directory, for a tracked path — and it is what the
# rule naming later asks `check-ignore -v` about, so the rule it names is the
# rule that fired, not a rule git would report for some other spelling.
scout_ignore_refused() {
  local root="$1" paths="" asked="" qs="" ign="" st="" sep=""
  paths="$(grep .)"
  [ -n "$paths" ] || return 0
  # BATCHED, because the per-path form spawned two git processes per path, on
  # every Scout run and every adoption. Measured over the 114 paths Scout asks
  # about on a small project: 2.1-2.2s per path, 0.03-0.04s batched, the same
  # 26 refused. The answers are the same questions asked once: which paths
  # the index has (any file, or any folder above one, as `ls-files
  # --error-unmatch` answers for a folder), then `check-ignore --stdin`, which
  # runs each path through the matcher the one-path form runs. Paths are
  # literal here, where `ls-files` would have read `*` in one as a glob.
  sep="$(printf '\001')"
  asked="$( { ( cd "$root" && git ls-files -z ) 2>/dev/null | tr '\0' '\n'; printf '%s\n' "$sep"; printf '%s\n' "$paths"; } \
    | awk -v SEP="$sep" '
        !s && $0 == SEP { s = 1; next }
        !s { t[$0] = 1; d = $0; while (sub(/\/[^\/]*$/, "", d)) t[d] = 1; next }
        $0 == "" { next }
        {
          q = $0
          if ($0 in t) { q = $0; if (!sub(/\/[^\/]*$/, "", q)) next }   # tracked: ask its folder; top-level: git add accepts it
          print $0 "\t" q
        }')"
  [ -n "$asked" ] || return 0
  qs="$(printf '%s\n' "$asked" | cut -f2 | LC_ALL=C sort -u)"
  ign="$( cd "$root" 2>/dev/null || exit 3
          printf '%s\n' "$qs" | tr '\n' '\0' | git check-ignore --no-index --stdin -z 2>/dev/null | tr '\0' '\n'
          printf '%s%s\n' "$sep" "${PIPESTATUS[2]}" )"
  st="${ign##*"$sep"}"; ign="${ign%"$sep"*}"
  case "$st" in
    0|1)
      { printf '%s\n' "$ign"; printf '%s\n' "$sep"; printf '%s\n' "$asked"; } | awk -F '\t' -v SEP="$sep" '
        !s && $0 == SEP { s = 1; next }
        !s { if ($0 != "") i[$0] = 1; next }
        ($2 in i) { print "R\t" $1 "\t" $2 }'   # BL-322-S3-REFUSED-ROW
      return 0 ;;
  esac
  # git could not answer for the batch (rc 128: a path beyond a symbolic link,
  # for one). Ask path by path, so the path it could not answer for is named.
  local rel="" q="" ci=0
  while IFS="$(printf '\t')" read -r rel q; do
    [ -n "$rel" ] || continue
    ci=0
    ( cd "$root" && git check-ignore --no-index -q -- "$q" ) 2>/dev/null || ci=$?
    case "$ci" in
      0) printf 'R\t%s\t%s\n' "$rel" "$q" ;;   # BL-311-IGNORE-RULE-SAME-PATH
      1) : ;;                                  # not ignored
      *) printf 'F\t%s\t%s\n' "$rel" "$ci"; return 2 ;;   # BL-225-ORACLE-FAIL-CLOSED
    esac
  done <<ASKED
$asked
ASKED
  return 0
}

# scout_ignore_rule_rows ROOT ROWS — for each `<refused path>\t<asked>` row,
# `<source>\t<line>\t<pattern>\t<refused path>\t<asked>` as `git check-ignore -v`
# names the rule. Returns 1, having named nothing it could not verify, when git
# cannot name a rule for every row.
scout_ignore_rule_rows() {
  local root="$1" rows="$2" rel="" q="" out="" src="" ln="" pat="" echoed=""
  local tab=""
  tab="$(printf '\t')"
  while IFS="$tab" read -r rel q; do
    [ -n "$rel" ] || continue
    out="$( cd "$root" 2>/dev/null && printf '%s\0' "$q" \
      | git check-ignore -v -z --stdin --no-index 2>/dev/null | tr '\0' '\n' )"
    src="$(printf '%s\n' "$out" | sed -n 1p)"
    ln="$(printf '%s\n' "$out" | sed -n 2p)"
    pat="$(printf '%s\n' "$out" | sed -n 3p)"
    echoed="$(printf '%s\n' "$out" | sed -n 4p)"
    case "$ln" in ''|*[!0-9]*) return 1 ;; esac
    [ -n "$src" ] && [ -n "$pat" ] && [ "$echoed" = "$q" ] || return 1
    case "$pat" in '!'*) return 1 ;; esac   # BL-311-IGNORE-RULE-NEGATED
    printf '%s\t%s\t%s\t%s\t%s\n' "$src" "$ln" "$pat" "$rel" "$q"
  done <<ROWS
$rows
ROWS
  return 0
}

# scout_ignore_rules_explain ROOT ROWS — `## BL-311:` row 5: for each
# `<refused path>\t<the path the decision asked about>` row, the ignore rule git
# reports, GROUPED BY RULE (one `lib/` refusing 24 paths is one entry, with its
# count), then the one-line fix where there is one. Prints nothing and returns
# 1 when git cannot name a rule for every row — the caller then keeps the block
# it always printed, and says how to ask git directly.
#
# WHAT GIT GIVES. `check-ignore -v -z --stdin` answers `<source> NUL <line> NUL
# <pattern> NUL <path> NUL`; `-z` needs `--stdin` (measured: "fatal: -z only
# makes sense with --stdin"). `--no-index` because the decision used it. For a
# path under an excluded directory git names the DIRECTORY's rule (measured on
# git 2.54.0, five rule orders). A `!` pattern means git found the path
# RE-INCLUDED — `-v` exits 0 for that too — which contradicts the decision, so
# it names nothing rather than a rule that did not fire.
#
# WHERE A RULE LIVES. A relative `.gitignore` is in the project, and nested
# ones anchor relative to their own directory. `info/exclude` belongs to this
# clone alone and is never committed. Anything else is outside the repository,
# and WHO ELSE READS IT depends on where it came from: git reads ONE personal
# excludes file — `core.excludesFile` when any config sets it, otherwise its
# default `${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore` — so the block asks git
# which config set it (`git config --show-scope`, read-only) and words it by
# that scope: a repository-local setting is read by this repository alone, a
# global one by every repository of this user's, a system one by every
# repository on the machine. A source matching neither path is named plainly.
#
# THE FIX IS SUGGESTED, NEVER MADE. A rule with no slash but a trailing one
# (`lib/`) matches at any depth; anchoring it (`/lib/`) is the one-line fix when
# the refused paths are not under the top-level match — and only the operator
# knows whether the rule meant "every lib/". When anchoring would still match,
# the block says so instead of offering it; a glob or an already-anchored rule
# gets "narrow or remove". Adoption never edits an ignore file.
#
# THE ROWS ARE SORTED FIRST (`## BL-322:` S3), so the order the rules are named
# in, and the example each names, do not depend on the order a caller found the
# paths in: Scout derives its set and adoption rehearses its own, and the two
# must say the same thing about the same tree.
scout_ignore_rules_explain() {
  local root="$1" rows="$2" table="" tab=""
  tab="$(printf '\t')"
  rows="$(printf '%s\n' "$rows" | LC_ALL=C sort)"   # BL-322-S3-EXPLAIN-SORT
  table="$(scout_ignore_rule_rows "$root" "$rows")" || return 1
  [ -n "$table" ] || return 1
  # `--type=path` expands `~/` the way git does, so the value compares equal to
  # the source `-v` printed (measured, git 2.54.0: both give the expanded path).
  local xs="" xscope="" xpath="" xword=""
  xs="$( cd "$root" 2>/dev/null && git config --show-scope --type=path --get core.excludesFile 2>/dev/null )" || xs=""   # BL-311-IGNORE-RULE-XPATH-EXPAND
  if [ -n "$xs" ]; then
    xscope="${xs%%"$tab"*}"; xpath="${xs#*"$tab"}"
    case "$xscope" in
      local|worktree) xword="core.excludesFile in this repository's own git config names it, so only this repository reads it" ;;   # BL-311-IGNORE-RULE-XSCOPE
      global) xword="core.excludesFile in your global git config names it, so every repository of yours reads it unless one sets its own" ;;
      system) xword="core.excludesFile in this machine's system git config names it, so every repository on this machine reads it unless one sets its own" ;;   # BL-311-IGNORE-RULE-XSCOPE-SYSTEM
      *) xword="core.excludesFile names it, set in $xscope config" ;;
    esac
  else
    xpath="${XDG_CONFIG_HOME:-${HOME:-}/.config}/git/ignore"   # BL-311-IGNORE-RULE-XDG
    xword="git's default personal excludes file, read because no git config sets core.excludesFile, so every repository of yours that sets none reads it"
  fi
  printf '%s\n' "$table" | XPATH="$xpath" XWORD="$xword" awk -F'\t' '
    {
      key = $1 FS $2 FS $3   # BL-311-IGNORE-RULE-GROUP
      if (!(key in n)) { k++; order[k] = key; src[key] = $1; ln[key] = $2; pat[key] = $3; ex[key] = $4 }
      n[key]++
      qs[key] = qs[key] "\n" $5
    }
    END {
      for (i = 1; i <= k; i++) {
        key = order[i]; s = src[key]; p = pat[key]; l = ln[key]
        where = s " (outside this repository: a git excludes file, not part of the project)"   # BL-311-IGNORE-RULE-OUTSIDE
        if (s == ENVIRON["XPATH"]) where = s " (outside this repository: " ENVIRON["XWORD"] ")"   # BL-311-IGNORE-RULE-XSOURCE
        if (s !~ /^\// && s ~ /(^|\/)\.gitignore$/) where = s
        if (s ~ /(^|\/)info\/exclude$/) where = s " (this clone only, never committed)"   # BL-311-IGNORE-RULE-EXCLUDE
        printf "  %s, line %s: `%s` refuses %d of them (for example %s)\n", where, l, p, n[key], ex[key]
        # A nested .gitignore anchors to its own directory, so its paths are
        # compared with that directory stripped, and the block names the
        # directory a path really sits under (`scripts/lib`, not "lib").
        base = ""
        if (s !~ /^\// && s ~ /\/\.gitignore$/) base = substr(s, 1, length(s) - 10)
        stem = p; sub(/\/$/, "", stem)
        floating = (p !~ /^[!\/\\]/ && stem != "" && stem !~ /[\/*?\[]/)
        helps = 1; hit = ""
        nq = split(qs[key], arr, "\n")
        for (j = 1; j <= nq; j++) {
          q = arr[j]; if (q == "") continue
          if (base != "" && index(q, base) == 1) q = substr(q, length(base) + 1)   # BL-311-IGNORE-RULE-BASE-STRIP
          c = split(q, comp, "/")
          if (comp[1] == stem) helps = 0
          if (hit == "") {
            acc = ""
            for (t = 1; t <= c; t++) { acc = acc (t > 1 ? "/" : "") comp[t]; if (comp[t] == stem) { hit = base acc; break } }
          }
        }
        top = (base == "" ? "at the top" : "directly in " base)
        if (!floating) printf "    Narrow or remove that line; which is right is your call. Adoption never edits your ignore files.\n"
        else if (!helps) printf "    Anchoring it would not help: the paths this adoption needs sit under %s, where `/%s` in %s still matches. Narrowing or removing the rule is your call. Adoption never edits your ignore files.\n", (base == "" ? "the top-level " stem : base stem), p, s   # BL-311-IGNORE-RULE-NO-ANCHOR
        else {
          printf "    It has no leading slash, so it matches `%s` at any depth, not only %s%s.\n", stem, top, (hit == "" ? "" : ": here it matched " hit)
          printf "    One-line fix, if the rule was meant for %s only: change line %s of %s to `/%s`.\n", (base == "" ? "the top-level " p : base p), l, s, p   # BL-311-IGNORE-RULE-ANCHOR
          printf "    Whether it was is your judgement: if it is meant to ignore every %s at any depth, anchoring it is wrong, and these files stay refused until the rule changes. Adoption never edits your ignore files.\n", p
        }
      }
    }'
}

# ── What adoption writes, as Scout can know it ──────────────────────────────

# _scout_ignore_is_framework FW — is FW a Solo Orchestrator clone, the place
# Scout's own files say adoption copies from? Scout copied out on its own (the
# standalone packaging, scripts/scout.sh header) has none beside it.
_scout_ignore_is_framework() {
  [ -f "$1/init.sh" ] && [ -d "$1/templates/generated" ]   # BL-322-S3-FW-GUARD
}

# _scout_ignore_under_link ROOT REL — a folder on REL's way is a symlink.
# adopt_path_under_link (scripts/lib/adopt/adopt-core.sh), by extraction.
_scout_ignore_under_link() {
  local root="$1" rest="$2" pre=""
  rest="${rest%/*}"
  [ "$rest" = "$2" ] && return 1        # no folder part
  while [ -n "$rest" ]; do
    pre="${pre:+$pre/}${rest%%/*}"
    [ -L "$root/$pre" ] && return 0   # BL-322-S3-SET-UNDER-LINK
    case "$rest" in */*) rest="${rest#*/}" ;; *) rest="" ;; esac
  done
  return 1
}

# _scout_ignore_kept ROOT REL — adoption's document writer leaves REL alone:
# it is a symlink, inside one, or a file adoption may not write
# (`_adopt_doc_put`'s kept-symlink and kept-readonly).
_scout_ignore_kept() {
  local root="$1" rel="$2"
  { [ -L "$root/$rel" ] || { [ -e "$root/$rel" ] && [ ! -w "$root/$rel" ]; }; } && return 0   # BL-322-S3-SET-KEEP
  _scout_ignore_under_link "$root" "$rel"
}

# scout_adoption_write_set FW ROOT [CIHOST] — every path an adoption of ROOT
# writes and records for its commit, whatever the operator answers, in the
# order of the write phase (`_adopt_write_phase`); duplicates are possible and
# harmless. CIHOST is the host Scout found (`stack.ciHost`), which is where
# adoption reads it from too. The classes left out are named in this file's
# header. Held equal to a real rehearsal by tests/test-bl322-s3-ignore-preflight.sh.
scout_adoption_write_set() {
  local fw="$1" root="$2" ci="${3:-}" rel="" base="" f="" s="" src=""
  # adopt_test_debt_record — the first write.
  printf '%s\n' .claude/test-debt.json
  # adopt_install_framework — every script init.sh copies, from init.sh's own
  # cp lines, read the way adoption's parser reads them
  # (soif_parse_shipped_scripts); one it cannot find in the clone it skips.
  grep -E 'cp[[:space:]]+"\$SCRIPT_DIR/scripts/' "$fw/init.sh" 2>/dev/null \
    | sed -n 's#.*cp[[:space:]]*"\$SCRIPT_DIR/\(scripts/[^"]*\)".*#\1#p' | while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if [ "${rel%/}" != "$rel" ]; then
      base="${rel#scripts/}"
      for f in "$fw/scripts/$base"*.sh; do [ -f "$f" ] && printf 'scripts/%s%s\n' "$base" "${f##*/}"; done
    else
      [ -f "$fw/$rel" ] && printf '%s\n' "$rel"   # BL-322-S3-SET-SCRIPTS
    fi
  done
  # _adopt_install_semgrep_config — only where the project has none.
  if [ -f "$fw/templates/semgrep/soif-dom-sinks.yml" ]; then
    if [ -e "$root/.semgrep/soif-dom-sinks.yml" ] || [ -L "$root/.semgrep/soif-dom-sinks.yml" ]; then :; else printf '%s\n' .semgrep/soif-dom-sinks.yml; fi   # BL-322-S3-SET-SEMGREP-ABSENT
  fi
  printf '%s\n' .claude/orchestrator-source.json
  # The state stages (_adopt_state_order): the approval log, phase state,
  # intake, dispositions and their audit rows, the stamp, the assessment
  # prompt, and the write set itself.
  printf '%s\n' APPROVAL_LOG.md .claude/phase-state.json .claude/process-state.json PROJECT_INTAKE.md \
    .claude/intake-progress.json .claude/adoption/scout-report.json .claude/adoption/secrets-dispositions.json \
    .claude/bypass-audit.json .claude/manifest.json .claude/adoption/assessment-prompt.md .claude/adoption/write-set.txt
  # The framework's documents (adopt_write_framework_docs), each through the
  # writer that leaves a symlink or a read-only file alone.
  for rel in CLAUDE.md FEATURES.md BUGS.md RELEASE_NOTES.md docs/INDEX.md docs/IDENTIFIERS.md docs/archive/README.md; do
    _scout_ignore_kept "$root" "$rel" || printf '%s\n' "$rel"
  done
  # The reference guides: init.sh's docs -> docs/reference copies, only where
  # the project has none.
  grep -E 'cp[[:space:]]+"\$SCRIPT_DIR/docs/[^"]*"[[:space:]]+docs/reference/' "$fw/init.sh" 2>/dev/null \
    | sed -n 's#.*cp[[:space:]]*"\$SCRIPT_DIR/docs/\([^"]*\)".*#\1#p' | while IFS= read -r src; do
      base="${src##*/}"
      [ -f "$fw/docs/$src" ] || continue
      if [ -e "$root/docs/reference/$base" ] || [ -L "$root/docs/reference/$base" ]; then continue; fi   # BL-322-S3-SET-REF-ABSENT
      _scout_ignore_kept "$root" "docs/reference/$base" || printf 'docs/reference/%s\n' "$base"
    done
  # The framework's CI (adopt_write_ci), at its own name for the host, where
  # there is none.
  rel=""
  case "$ci" in github) rel=.github/workflows/solo-gates.yml ;; gitlab) rel=.gitlab-ci-solo.yml ;; bitbucket) rel=bitbucket-pipelines.solo.yml ;; esac   # BL-322-S3-SET-CI
  if [ -n "$rel" ] && [ ! -e "$root/$rel" ] && [ ! -L "$root/$rel" ] && ! _scout_ignore_under_link "$root" "$rel"; then
    printf '%s\n' "$rel"
  fi
  # The session layer (adopt_write_session_layer): the settings unless they
  # are a symlink, .claude/.gitignore where there is none, the skills.
  if ! { [ -L "$root/.claude/settings.json" ] || _scout_ignore_under_link "$root" .claude/settings.json; }; then
    printf '%s\n' .claude/settings.json
  fi
  if [ -e "$root/.claude/.gitignore" ] || [ -L "$root/.claude/.gitignore" ] || _scout_ignore_under_link "$root" .claude/.gitignore; then :; else printf '%s\n' .claude/.gitignore; fi   # BL-322-S3-SET-IGNORE-ABSENT
  for f in "$fw/templates/generated/skills/"*/SKILL.md; do
    [ -f "$f" ] || continue
    s="${f%/SKILL.md}"; s="${s##*/}"
    _scout_ignore_kept "$root" ".claude/skills/$s/SKILL.md" || printf '%s\n' ".claude/skills/$s/SKILL.md"
    if [ -f "$fw/templates/generated/skills/$s/NOTICE" ] && [ ! -e "$root/.claude/skills/$s/NOTICE" ]; then   # BL-322-S3-SET-NOTICE-ABSENT
      _scout_ignore_kept "$root" ".claude/skills/$s/NOTICE" || printf '%s\n' ".claude/skills/$s/NOTICE"
    fi
  done
  return 0
}

# scout_ignore_scan ROOT WORK FW — the report's `collisions.ignoreRules`.
#
# Writes, inside WORK: ignchecked (1 when the answer is known), ignblock (1 when
# adoption would stop), ignpaths (how many paths were asked about), ignwhy (why
# it was not checked), ignrefused (the refused paths, sorted), ignrules
# (`<source>\t<line>\t<pattern>\t<count>\t<example>`, one row per rule) and
# ignexplain (the lines adoption's block would print about the rules).
scout_ignore_scan() {
  local root="$1" work="$2" fw="$3" paths="" rows="" st=0 frow="" n=0 expl=""
  printf '0\n' > "$work/ignchecked"; printf '0\n' > "$work/ignblock"; printf '0\n' > "$work/ignpaths"
  : > "$work/ignwhy"; : > "$work/ignrefused"; : > "$work/ignrules"; : > "$work/ignexplain"
  if ! _scout_ignore_is_framework "$fw"; then
    printf '%s\n' "Scout is not running from a Solo Orchestrator framework clone, so it does not know which files adoption writes. Run the scripts/scout.sh inside the framework's folder to have this checked." > "$work/ignwhy"
    return 0
  fi
  if ! ( cd "$root" && git rev-parse --is-inside-work-tree ) >/dev/null 2>&1; then
    printf '%s\n' "This is not a git repository, so there are no ignore rules to ask about. Adoption needs one." > "$work/ignwhy"
    return 0
  fi
  paths="$(scout_adoption_write_set "$fw" "$root" "$(head -1 "$work/cihost" 2>/dev/null)" \
    | awk '$0 != "APPROVAL_LOG.md" && $0 != ".claude/bypass-audit.json"' | LC_ALL=C sort -u)"   # BL-322-S3-STAGEABLE-ONLY
  n="$(printf '%s\n' "$paths" | grep -c .)"
  printf '%s\n' "$n" > "$work/ignpaths"
  rows="$(printf '%s\n' "$paths" | scout_ignore_refused "$root")" || st=$?
  if [ "$st" -ne 0 ]; then
    frow="$(printf '%s\n' "$rows" | awk -F '\t' '$1 == "F" { print $2 " (git check-ignore exited " $3 ")"; exit }')"
    printf '%s\n' "git could not say whether ${frow:-one of them} is covered by your ignore rules, and adoption stops there too, before it writes anything." > "$work/ignwhy"
    printf '1\n' > "$work/ignblock"
    return 0
  fi
  printf '1\n' > "$work/ignchecked"
  rows="$(printf '%s\n' "$rows" | awk -F '\t' '$1 == "R" { print $2 "\t" $3 }' | LC_ALL=C sort)"
  [ -n "$rows" ] || return 0
  printf '1\n' > "$work/ignblock"
  printf '%s\n' "$rows" | cut -f1 > "$work/ignrefused"
  if expl="$(scout_ignore_rules_explain "$root" "$rows")" && [ -n "$expl" ]; then
    printf '%s\n' "$expl" > "$work/ignexplain"
    scout_ignore_rule_rows "$root" "$rows" | awk -F '\t' '
      { k = $1 FS $2 FS $3; if (!(k in n)) { o[++c] = k; ex[k] = $4 }; n[k]++ }
      END { for (i = 1; i <= c; i++) print o[i] "\t" n[o[i]] "\t" ex[o[i]] }' > "$work/ignrules"
  else
    printf '%s\n' "git could not name the rule that refuses them (\`git check-ignore -v\` did not answer). Ask it about each path above:" \
      "  git check-ignore -v --no-index -- <path>" > "$work/ignexplain"
  fi
  return 0
}

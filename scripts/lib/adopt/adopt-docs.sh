#!/usr/bin/env bash
# scripts/lib/adopt/adopt-docs.sh — WP12b: the framework documents an adopted
# project receives.
#
# SPEC: `## BL-242:` D3 — "an adopted project gets documents that match the
# framework's documentation requirements … The old documents are archived in the
# project for historical purposes" — and its 2026-08-31 reach ruling: the
# originals are archived, never deleted, and adoption "must NAME them to the
# operator with an explicit invitation to retrieve content from the archive and
# add it to the new files. The informing is part of the requirement."
#
# ─────────────────────────────────────────────────────────────────────────────
# WHY THIS MATTERS MORE THAN ITS SIZE. `CLAUDE.md` is what an agent reads at the
# start of every session. An adopted project without one starts every session
# with no orientation — which gates exist, which scripts to run, where the
# guides are. Adoption put the gates and scripts in place and then left the one
# file that tells an agent they are there. `adopt_stub_project_docs` said so on
# every run.
#
# WHAT IS WRITTEN, AND WHY EXACTLY THIS SET. The same documents `init.sh` gives
# a scaffolded project at the same moment, through the same sources:
#   CLAUDE.md                 rendered by the SHARED `soif_render_claude_md`
#   FEATURES.md BUGS.md RELEASE_NOTES.md docs/INDEX.md docs/IDENTIFIERS.md
#   docs/archive/README.md    copied from the same templates `init.sh` copies
#   docs/reference/*.md       the eight guides `init.sh` copies — CLAUDE.md
#                             points an agent at three of them by path, so
#                             writing it without them hands over broken
#                             references
# NOT `PROJECT_BIBLE.md` or `PRODUCT_MANIFESTO.md`: `init.sh` does not write
# those either — they are phase outputs, produced when the phases run.
#
# THE "ADAPT OR MERGE" HALF OF D3 IS NOT HERE, AND SAYING SO IS THE POINT. D3
# asks for documents "adapted or merged from what the project already has".
# Adapting prose is judgement, and judgement is Act 3's — the assessment, a
# Claude Code session, which is not built. What a shell step can do honestly is
# lay down the framework's documents, keep every original in the archive, and
# tell the operator by name so the merge can happen — by them now, or by the
# assessment later.
#
# ─────────────────────────────────────────────────────────────────────────────
# NEVER WRITE THROUGH A LINK, NEVER DESTROY WHAT THE ARCHIVE CANNOT GIVE BACK.
# The commit-time hook's review found that a plain `printf >` follows a symlink
# out of the repository (a shared file became 1707 lines of framework hook) and
# writes into a HARDLINK's shared inode. A document is the same shape. So:
#   - a SYMLINK at the path is left alone (the archive collects plain files, so
#     there is no copy to restore from, and the target may be shared);
#   - a READ-ONLY file is left alone;
#   - everything else is written BESIDE the path and RENAMED over it, which
#     replaces the directory entry and leaves any shared inode untouched.
# The guides under docs/reference are written only where ABSENT: they are the
# framework's own copies, a file already there is the operator's, and "write
# only what is not there" keeps them out of I20's overwrite inventory.

# The templates `init.sh` copies verbatim, as "SOURCE-RELATIVE-TO-FRAMEWORK
# DESTINATION" pairs. Spelled once so the writer and the archive's dispositions
# cannot disagree about which documents are replaced.
_adopt_doc_copies() {                                  # BL-242-DOCS-SET
  printf '%s\t%s\n' \
    templates/generated/features.tmpl       FEATURES.md \
    templates/generated/bugs.tmpl           BUGS.md \
    templates/generated/release-notes.tmpl  RELEASE_NOTES.md \
    templates/generated/doc-index.tmpl      docs/INDEX.md \
    templates/generated/identifiers.tmpl    docs/IDENTIFIERS.md \
    templates/generated/archive-readme.tmpl docs/archive/README.md
}
_adopt_doc_references() {                              # BL-242-DOCS-REFERENCE
  printf '%s\n' builders-guide.md governance-framework.md executive-review.md \
    cli-setup-addendum.md user-guide.md messaging-standard.md security-scan-guide.md \
    uat-authoring-guide.md
}

# _adopt_doc_value FILE JQPATH FALLBACK PATTERN — a value from the recorded
# intake, used ONLY if it matches PATTERN. `soif_render_claude_md` puts
# platform, track and language into a sed replacement UNESCAPED, because
# `init.sh` validates them first; adoption must hold the same line, or a value
# carrying `|`, `&` or `\` would corrupt the render.
_adopt_doc_value() {
  local v
  v="$(jq -r "$2 // \"\"" "$1" 2>/dev/null)"
  # A newline defeats the pattern: `grep` passes if ANY line matches, and a
  # second line reaches sed as a command of its own (`w FILE` was measured).
  case "$v" in *[[:cntrl:]]*) printf '%s' "$3"; return 0 ;; esac
  if printf '%s' "$v" | grep -Eq "$4"; then printf '%s' "$v"; else printf '%s' "$3"; fi
}

# ─────────────────────────────────────────────────────────────────────────────
# `## BL-322:` S2 — THE PROJECT'S OWN RULES KEEP LOADING (dogfood run 3,
# findings 2, 8, 9). Replacing CLAUDE.md also dropped its `@` imports: k-pdf's
# PROJECT_BIBLE.md, PRODUCT_MANIFESTO.md, CONTRIBUTING.md and intake were still
# in the tree, untouched, and stopped loading, and with them the colour-alone
# HARD CONSTRAINT, the architecture rules and the never-do list (the Bible holds
# all three), until the assessment folded them back in. Nothing said so.
#
# KARL'S DECISION (2026-10-07). Carry the original's RELATIVE imports of
# REGULAR IN-REPO files adoption did not write into a marked section of the new
# CLAUDE.md; name every import not carried, with the reason; `~/` and absolute
# imports are NAMED ONLY, never carried (they may not exist on another
# machine); warn that the rules written inside the old file itself load again
# only once the assessment folds them in. Those inline rules are not carried:
# telling a lasting rule from a stale claim ("Phase: 2", "Next: merge the
# branch") is judgement, and judgement is the assessment's.
#
# WHAT COUNTS AS AN IMPORT is Claude Code's rule, read conservatively
# (code.claude.com/docs/en/memory): `@path` anywhere in the file except inside a
# fenced block or a code span; a backslash before a space keeps the space in the
# path; a quoted path is not an import; a relative path resolves against the
# file holding it — the project root, for both the old CLAUDE.md and the new
# one, so a carried line is copied AS WRITTEN. The `@` must start the line or
# follow whitespace, so an address (`karl@example.com`) is not one. Anything
# this reading misses that Claude Code would import is, at worst, not carried —
# and the file is in the archive, which the warning names.
ADOPT_CARRY_BEGIN='<!-- SOIF-CARRIED-IMPORTS-BEGIN (BL-322) -->'
ADOPT_CARRY_END='<!-- SOIF-CARRIED-IMPORTS-END -->'
ADOPT_CLAUDE_MD_REPLACED=0

# _adopt_claude_md_import_tokens FILE — each import in FILE, once, as written
# (without the `@`), in file order.
_adopt_claude_md_import_tokens() {
  awk '
    {
      line = $0
      if (fence == "`") { if (line ~ /^ ? ? ?```/) fence = ""; next }
      if (fence == "~") { if (line ~ /^ ? ? ?~~~/) fence = ""; next }
      if (line ~ /^ ? ? ?```/) { fence = "`"; next }   # BL-322-CARRY-FENCE
      if (line ~ /^ ? ? ?~~~/) { fence = "~"; next }   # BL-322-CARRY-TILDE
      gsub(/`[^`]*`/, "", line)   # BL-322-CARRY-SPAN
      s = " " line
      while ((i = index(s, "@")) > 0) {
        pre = substr(s, i - 1, 1)
        s = substr(s, i + 1)
        if (pre != " " && pre != "\t") continue   # BL-322-CARRY-WS
        tok = ""
        while (length(s) > 0) {
          c = substr(s, 1, 1)
          if (c == "\\" && substr(s, 2, 1) == " ") { tok = tok "\\ "; s = substr(s, 3); continue }
          if (c == " " || c == "\t") break
          tok = tok c
          s = substr(s, 2)
        }
        if (tok !~ /^[A-Za-z0-9._~\/-]/) continue   # BL-322-CARRY-PATHCHAR
        if (!(tok in seen)) { seen[tok] = 1; print tok }
      }
    }' "$1"
}

# _adopt_carry_norm PATH — PATH with `.` and `..` resolved lexically (as Claude
# Code resolves an import), relative to the root. Fails when it leaves the root.
_adopt_carry_norm() {
  local rest="$1" out="" seg=""
  while [ -n "$rest" ]; do
    seg="${rest%%/*}"
    case "$rest" in */*) rest="${rest#*/}" ;; *) rest="" ;; esac
    case "$seg" in
      ''|.) ;;
      ..) [ -n "$out" ] || return 1
          case "$out" in */*) out="${out%/*}" ;; *) out="" ;; esac ;;
      *)  out="${out:+$out/}$seg" ;;
    esac
  done
  printf '%s' "${out:-.}"
}

# _adopt_claude_md_carry ROOT FILE — one row per import in FILE:
#   carry<TAB>TOKEN, or skip<TAB>TOKEN<TAB>REASON
# REASON is home, outside, link, missing, not-a-file, archived or written.
# Asked BEFORE this stage writes anything, so "adoption did not write it" is two
# questions: the ledger of what earlier stages wrote, and the archive's
# forward-looking dispositions — which already say what THIS and later stages
# will replace (FEATURES.md here, `.claude/settings.json` in the session layer).
_adopt_claude_md_carry() {                             # BL-322-CARRY
  local root="$1" src="$2" tok="" path="" norm="" reason="" mj="" written=""
  [ -n "${ADOPT_ARCHIVE_DIR:-}" ] && mj="$root/$ADOPT_ARCHIVE_DIR/MANIFEST.json"
  written="$(adopt_written_paths)"
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    path="$(printf '%s' "$tok" | sed 's/\\ / /g')"
    reason=""; norm=""
    case "$path" in '~'*|/*) reason=home ;; esac   # BL-322-CARRY-HOME
    if [ -z "$reason" ]; then
      norm="$(_adopt_carry_norm "$path")" || reason=outside   # BL-322-CARRY-OUTSIDE
    fi
    if [ -z "$reason" ]; then
      if [ -L "$root/$norm" ] || adopt_path_under_link "$root" "$norm"; then reason=link   # BL-322-CARRY-LINK
      elif [ ! -e "$root/$norm" ]; then reason=missing   # BL-322-CARRY-MISSING
      elif [ ! -f "$root/$norm" ]; then reason=not-a-file   # BL-322-CARRY-NOTFILE
      elif [ -n "$mj" ] && jq -e --arg p "$norm" '[.entries[] | select(.originalPath == $p and .disposition != "kept")] | length > 0' "$mj" >/dev/null 2>&1; then reason=archived   # BL-322-CARRY-ARCHIVED
      elif printf '%s\n' "$written" | grep -qxF -- "$norm"; then reason=written   # BL-322-CARRY-WRITTEN
      fi
    fi
    if [ -z "$reason" ]; then printf 'carry\t%s\n' "$tok"; else printf 'skip\t%s\t%s\n' "$tok" "$reason"; fi
  done <<TOKENS
$(_adopt_claude_md_import_tokens "$src")
TOKENS
}

# _adopt_carry_reason REASON — the reason, for a person.
_adopt_carry_reason() {
  case "$1" in
    home)       printf 'in your home folder, or an absolute path: named only, never carried — it may not exist on another machine' ;;
    outside)    printf 'outside this project' ;;
    link)       printf 'a symlink, or inside a symlinked folder' ;;
    missing)    printf 'no such file in this project' ;;
    not-a-file) printf 'not a file' ;;
    archived)   printf 'adoption replaced or changed that file, so it no longer holds what you imported; yours is in the archive' ;;
    written)    printf 'adoption wrote that file; it is not one of yours' ;;
    *)          printf '%s' "$1" ;;
  esac
}

# _adopt_carry_section ROWS ARCHIVED_COPY — the section the new CLAUDE.md gets.
_adopt_carry_section() {
  printf '\n%s\n' "$ADOPT_CARRY_BEGIN"
  printf '## Carried over from your CLAUDE.md\n\n'
  printf "Adoption replaced this project's own CLAUDE.md. The original is archived at\n"
  printf '`%s`.\n' "$2"
  printf 'It imported the files below, which are still in the project, so they keep loading:\n\n'
  printf '%s\n' "$1" | awk -F '\t' '$1 == "carry" { print "@" $2 }'
  printf '\nOnly its imports were carried. The rules written in the original file itself\n'
  printf 'load again only once the adoption assessment folds what is worth keeping into\n'
  printf 'this file; the assessment then keeps or drops each import above and deletes\n'
  printf 'this section. Where an imported file disagrees with the rest of this file, say\n'
  printf 'so rather than choosing one silently.\n'
  printf '%s\n' "$ADOPT_CARRY_END"
}

# _adopt_doc_put ROOT REL SRC — put SRC at REL, or leave REL alone and say why.
# Echoes one of: written | replaced | kept-symlink | kept-readonly.
_adopt_doc_put() {                                     # BL-242-DOCS-PUT
  local root="$1" rel="$2" src="$3" dst tmp had=0
  dst="$root/$rel"
  if [ -L "$dst" ] || adopt_path_under_link "$root" "$rel"; then printf 'kept-symlink'; return 0; fi   # BL-242-PARENT-LINK
  [ -e "$dst" ] && had=1
  if [ "$had" -eq 1 ] && [ ! -w "$dst" ]; then printf 'kept-readonly'; return 0; fi
  adopt_touched_disk   # BL-225-TOUCHED-DISK
  mkdir -p "$(dirname "$dst")" 2>/dev/null || { adopt_refuse "could not create $(dirname "$rel")"; return 1; }
  tmp="$dst.soif-new.$$"
  rm -f "$tmp" 2>/dev/null
  adopt_touched_disk   # BL-225-TOUCHED-DISK
  cp "$src" "$tmp" 2>/dev/null && mv -f "$tmp" "$dst" 2>/dev/null \
    || { rm -f "$tmp" 2>/dev/null; adopt_refuse "could not write $rel"; return 1; }
  adopt_record_write "$rel"
  if [ "$had" -eq 1 ]; then printf 'replaced'; else printf 'written'; fi
}

# adopt_write_framework_docs ROOT — the stage.
adopt_write_framework_docs() {                         # BL-242-DOCS-STAGE
  local root="$1" fw="$ADOPT_FRAMEWORK_ROOT" ip="$1/.claude/intake-progress.json"
  local src rel out replaced="" kept="" name desc platform track language rendered
  local carry="" tok="" why="" arc_claude=""
  command -v soif_render_claude_md >/dev/null 2>&1 \
    || { adopt_refuse "the CLAUDE.md renderer is not loaded (scripts/lib/render-project-docs.sh)"; return 1; }

  # `## BL-322:` S2 — read the project's own CLAUDE.md BEFORE anything here is
  # written. A symlink is left alone below, so there is nothing to carry.
  ADOPT_CLAUDE_MD_REPLACED=0
  if [ -f "$root/CLAUDE.md" ] && [ ! -L "$root/CLAUDE.md" ]; then
    carry="$(_adopt_claude_md_carry "$root" "$root/CLAUDE.md")"
  fi
  arc_claude="${ADOPT_ARCHIVE_DIR:-the adoption archive}/CLAUDE.md"

  # ── CLAUDE.md, through the shared renderer ────────────────────────────────
  # Rendered to a scratch file first and then PUT, so it goes through the same
  # link-and-permission rule as every other document.
  name="${ADOPT_PROJECT_NAME:-this project}"
  desc="$(jq -r '.description // ""' "$ip" 2>/dev/null)"
  [ -n "$desc" ] || desc="Not yet recorded — asked in the assessment."
  platform="$(_adopt_doc_value "$ip" .platform undecided '^[a-z_]+$')"
  track="$(_adopt_doc_value "$ip" .track undecided '^(light|standard|full)$')"
  language="$(_adopt_doc_value "$ip" .language undecided '^[A-Za-z0-9_+#.-]+$')"
  rendered="$ADOPT_WORK/claude-md.rendered"
  soif_render_claude_md "$fw/templates/generated/claude-md.tmpl" "$rendered" \
    "$name" "$desc" "$platform" "$track" "$language" 2 "${ADOPT_DEPLOYMENT:-personal}" \
    || { adopt_refuse "could not render CLAUDE.md from the framework's template"; return 1; }
  # A render that exits 0 having written nothing is not a document.
  [ -s "$rendered" ] || { adopt_refuse "CLAUDE.md rendered empty"; return 1; }
  # `## BL-322:` S2 — the carried section, before TL;DR's: `reconfigure-project.sh`
  # removes TL;DR's section and appends it again, so TL;DR's stays last either way.
  if printf '%s\n' "$carry" | grep -q '^carry'; then
    _adopt_carry_section "$carry" "$arc_claude" >> "$rendered" || { adopt_refuse "could not add the carried imports to CLAUDE.md"; return 1; }   # BL-322-CARRY-APPEND
  fi
  # `## BL-312:` the TL;DR Mode section, when the operator said yes — added to
  # the render before it is PUT, so it follows the same link-and-permission rule.
  if [ "${ADOPT_TLDR_MODE:-false}" = true ]; then
    soif_tldr_apply_claude_md "$rendered" on || { adopt_refuse "could not add the TL;DR Mode section to CLAUDE.md"; return 1; }   # BL-312-ADOPT-TLDR-DOCS
  fi
  out="$(_adopt_doc_put "$root" CLAUDE.md "$rendered")" || return 1
  case "$out" in
    replaced) replaced="$replaced CLAUDE.md"; ADOPT_CLAUDE_MD_REPLACED=1 ;;   # BL-322-CARRY-FLAG
    kept-*) kept="$kept CLAUDE.md:${out#kept-}" ;;
  esac

  # ── the templates init.sh copies ─────────────────────────────────────────
  while IFS="$(printf '\t')" read -r src rel; do
    [ -n "$src" ] || continue
    [ -f "$fw/$src" ] || { adopt_refuse "the framework template $src is missing"; return 1; }
    out="$(_adopt_doc_put "$root" "$rel" "$fw/$src")" || return 1
    case "$out" in replaced) replaced="$replaced $rel" ;; kept-*) kept="$kept $rel:${out#kept-}" ;; esac
  done <<DOCS
$(_adopt_doc_copies)
DOCS

  # ── the reference guides, only where absent ───────────────────────────────
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    [ -f "$fw/docs/$rel" ] || continue
    if [ -e "$root/docs/reference/$rel" ] || [ -L "$root/docs/reference/$rel" ]; then continue; fi
    out="$(_adopt_doc_put "$root" "docs/reference/$rel" "$fw/docs/$rel")" || return 1
    case "$out" in kept-*) kept="$kept docs/reference/$rel:${out#kept-}" ;; esac
  done <<REFS
$(_adopt_doc_references)
REFS

  # ── D3: NAME THEM, AND INVITE THE MERGE ───────────────────────────────────
  # Under its own heading: printed bare, these lines ran straight on from the
  # `NOT DONE` block above them and read as part of it.
  adopt_head "The framework's documents"
  adopt_note "Wrote the framework's documents — CLAUDE.md, FEATURES.md, BUGS.md, RELEASE_NOTES.md,"
  adopt_note "docs/INDEX.md, docs/IDENTIFIERS.md, docs/archive/README.md and the guides in"
  adopt_note "docs/reference/ — except any listed below as left alone, and any guide you already had."
  if [ -n "$replaced" ]; then
    adopt_note "These replaced documents of yours:"
    for rel in $replaced; do adopt_say "     $rel"; done
    adopt_note "Your originals are in ${ADOPT_ARCHIVE_DIR:-the adoption archive}, each with a restore line in its"
    adopt_note "MANIFEST.md. Nothing in them was merged into the new files — copy across anything you"
    adopt_note "want to keep, or leave it for the assessment conversation to fold in."
  fi
  # `## BL-322:` S2 — the warning run 3 did not get, and what was carried.
  if [ "${ADOPT_CLAUDE_MD_REPLACED:-0}" = 1 ]; then   # BL-322-CARRY-ONLY-REPLACED
    adopt_blank
    adopt_say "   YOUR OWN CLAUDE.md IS NO LONGER WHAT CLAUDE CODE LOADS."   # BL-322-CARRY-WARN
    adopt_note "The rules written in it load again only once the assessment folds them into the"
    adopt_note "new CLAUDE.md. Until then, tell the agent any rule it must keep. Yours is"
    adopt_note "$arc_claude."
    if printf '%s\n' "$carry" | grep -q '^carry'; then
      adopt_note "Its imports of files still in this project were carried into the new CLAUDE.md,"
      adopt_note "under \"Carried over from your CLAUDE.md\", so those files keep loading:"
      printf '%s\n' "$carry" | while IFS="$(printf '\t')" read -r why tok _; do
        [ "$why" = carry ] && adopt_say "     @$tok"
      done
    elif [ -z "$carry" ]; then
      adopt_note "It imported no files, so nothing was carried over."
    fi
    if printf '%s\n' "$carry" | grep -q '^skip'; then
      adopt_note "These imports in it were NOT carried; add back any you need by hand:"
      printf '%s\n' "$carry" | while IFS="$(printf '\t')" read -r why tok rel; do
        [ "$why" = skip ] && adopt_say "     @$tok — $(_adopt_carry_reason "$rel")"
      done
    fi
  fi
  if [ -n "$kept" ]; then
    adopt_note "These were LEFT ALONE, so the framework's version of each is NOT in place:"
    for rel in $kept; do
      case "${rel##*:}" in
        symlink)  adopt_say "     ${rel%:*} — a symlink, or inside a symlinked folder; writing through it could overwrite a file elsewhere" ;;
        readonly) adopt_say "     ${rel%:*} — read-only" ;;
      esac
    done
  fi
  return 0
}

#!/usr/bin/env bash
# scripts/lib/adopt/adopt-archive.sh — §7's COLLISION ARCHIVE: the inventory,
# the archive tree and its MANIFEST, the plain disclosure, the recorded re-add,
# and §7.3's archive-secrets refusal.
#
# SPEC: docs/designs/2026-08-02-brownfield-adoption-v1.md §7.1 (the four
# buckets, and the vocabulary is reused rather than reinvented), §7.2 (the
# layout, the MANIFEST, and the five properties inherited from
# `_upgrade_snapshot_pre_mutation` in scripts/upgrade-project.sh), §7.3
# (disclosure, re-adds, the warning, and THE NEW EXPOSURE this design creates),
# §6.2 (redaction is a PROJECTION, not a flag), §8.9 (the `adoption_event` row
# and the five surfaces a new row type touches), §12-5, §10-WP6.
#
# ─────────────────────────────────────────────────────────────────────────────
# THE ONE SENTENCE THIS FILE EXISTS TO IMPLEMENT
#
# The operator's own configuration is copied somewhere they can get it back
# from, every copy is named out loud with a restore line, and NOTHING is
# committed until a secret scanner has looked at it.
#
# ─────────────────────────────────────────────────────────────────────────────
# §7.3'S EXPOSURE, IN THE PLAINEST TERMS, BECAUSE IT IS THE REASON THIS FILE IS
# WRITTEN THE WAY IT IS
#
# `.git/hooks/` is NOT tracked by git. `.claude/` IS. So copying a hook into
# the archive and staging the archive takes a file git has never seen — a file
# that may hold a token the operator put there precisely because it would never
# be committed — and COMMITS IT. Adoption would create the leak. The same is
# true of any `.claude/settings.local.json` the operator gitignored.
#
# So: the archive is written, then SCANNED, and only then staged, and an entry
# the scanner matched is never handed to `git add`. The refusal is per ENTRY,
# not per run — a secret in one hook must not cost the operator the record of
# everything else.
#
# AND WHEN NOBODY LOOKED, NOTHING IS STAGED. If gitleaks is absent or the scan
# fails, every entry is withheld. "We could not check" and "we checked and it
# is clean" are different claims and only one of them may result in a commit.
# The archive is still written to disk and still disclosed — the operator keeps
# their copy — it simply does not enter version control on an unexamined tree.
#
# ─────────────────────────────────────────────────────────────────────────────
# THE PROJECTION (§6.2's doctrine, applied to a surface §6.2 does not mention)
#
# gitleaks emits EIGHTEEN fields per finding and `--redact` covers exactly two
# of them, `Secret` and `Match`. It does NOT touch `Message` — the full commit
# message — which WP2 demonstrated carries a planted key straight through a
# "redacted" report. Nothing here passes the tool's report through: the one
# read of it NAMES the three fields it wants and can express no other. A field
# gitleaks adds in a future release is dropped because it was never named.
#
# THE ARCHIVE SCAN IS A `gitleaks dir` OVER THE ARCHIVE DIRECTORY ALONE, and
# that has a second, deliberate property: the adoptee's own `.gitleaks.toml`
# lives at their project root, not inside the archive, so a REPO-LOCAL config
# that allowlists `AKIA[A-Z2-7]{16}` cannot suppress this scan. A clean bill of
# health issued under rules written by the thing being audited is a different
# claim, and this is the one place the framework refuses to accept it.
#
# THAT ARGUMENT COVERS THE FILE AND NOT THE ENVIRONMENT, and saying so is the
# difference between a property and a slogan: `GITLEAKS_CONFIG` and
# `GITLEAKS_CONFIG_TOML` outrank the scanned path entirely and are inherited
# from whatever launched the driver. They are unset inside the scan subshell
# for exactly that reason — see the scrub in `adopt_archive_scan`.
#
# ─────────────────────────────────────────────────────────────────────────────
# M2/M3: this file is MODULE code. It sources nothing itself — the driver
# sources its libs in order — and it uses `bypass_audit_append` from
# scripts/lib/bypass-audit.sh, which scripts/adopt-project.sh declares in its
# M2 header. No core file names this file; that is M3 and the boundary lint
# proves it.
#
# bash-3.2 safe: no associative arrays, no `${var,,}`, no `((x++))`.

# ── The archive-and-replace population (§7.1's first row), spelled ONCE ─────
#
# Their AI-layer surfaces — Claude settings, skills, MCP connections — and
# their git hooks. NOT their pipelines (§7.4's carve-out: audited, never
# touched) and NOT their project files (§7.5: keep theirs).
#
# `.git/hooks/*.sample` IS EXCLUDED, and the exclusion is not cosmetic: git
# ships thirteen of them in every repository, none is ever active, and
# archiving them would bury the two or three hooks the operator actually wrote
# in a list nobody reads. The disclosure's value is that a person can read it.
_adopt_archive_ai_surfaces() {
  cat <<'SURFACES'
.claude/settings.json
.claude/settings.local.json
.mcp.json
SURFACES
}

# adopt_archive_inventory ROOT — one `<originalPath>\t<class>\t<archivedPath>`
# row per archive-and-replace surface THAT EXISTS.
#
# "ONLY FILES THAT EXIST ARE ARCHIVED" is §7.2's inherited property and it is
# expressed here, at the inventory, rather than by a later `[ -f ]` before each
# copy: a surface that is absent produces NO ROW, so it cannot reach the
# MANIFEST, the disclosure or the staging list by any path. A phantom entry for
# a file the operator never had is worse than a missing one — it teaches them
# the record is fiction.
adopt_archive_inventory() {
  local root="$1"
  local rel h base
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    [ -f "$root/$rel" ] || continue
    printf '%s\t%s\t%s\n' "$rel" "ai-settings" "$rel"
  done <<AI
$(_adopt_archive_ai_surfaces)
AI

  # ── APPROVAL_LOG.md, AND IT IS HERE BECAUSE WP9b MADE IT A REPLACE ────────
  # §7.1's rule is not "AI surfaces are archived", it is "every
  # archive-and-replace surface produces a row". Until A4 nothing in adoption
  # wrote this path, so it belonged to §7.5 (keep theirs) and correctly had no
  # row. A4 renders the tier-matched template OVER it, which makes it a
  # replace — and a replace with no row is the silent-success class this whole
  # archive exists to close.
  #
  # MEASURED BEFORE THE FIX, on an adoptee whose own APPROVAL_LOG.md was never
  # committed: rc 0, the operator's sign-off record gone, ZERO blobs anywhere
  # in the repository containing it, and the run printing "Nothing was
  # deleted." in the same transcript. The disclosure was telling the truth
  # about the list it had been given; the list was wrong.
  #
  # ITS OWN CLASS, NOT `document`. WP11 owns the `document` class (D3) and
  # folding this into it now would poach that package's vocabulary and its
  # notice text. A named class costs one row here and leaves WP11 free to
  # absorb it deliberately.
  if [ -f "$root/APPROVAL_LOG.md" ]; then
    printf '%s\t%s\t%s\n' "APPROVAL_LOG.md" "approval-log" "APPROVAL_LOG.md"
  fi

  # Skills are a directory shape, not a fixed path, so they are globbed. `find`
  # rather than a glob because bash 3.2 has no `nullglob` and an unmatched glob
  # would be passed through as a literal path.
  if [ -d "$root/.claude/skills" ]; then
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      printf '%s\t%s\t%s\n' "$rel" "skill" "$rel"
    done <<SKILLS
$( cd "$root" 2>/dev/null && find .claude/skills -type f -name 'SKILL.md' 2>/dev/null | LC_ALL=C sort )
SKILLS
  fi

  # Git hooks. Archived under `git-hooks/` and not `.git/hooks/`, exactly as
  # §7.2's tree shows: an archive directory containing a literal `.git`
  # subdirectory is a trap for every tool that walks a tree looking for one.
  if [ -d "$root/.git/hooks" ]; then
    while IFS= read -r h; do
      [ -n "$h" ] || continue
      base="${h##*/}"
      case "$base" in *.sample) continue ;; esac
      printf '%s\t%s\t%s\n' ".git/hooks/$base" "git-hook" "git-hooks/$base"
    done <<HOOKS
$( cd "$root" 2>/dev/null && find .git/hooks -maxdepth 1 -type f 2>/dev/null | LC_ALL=C sort )
HOOKS
  fi
  return 0
}

# ── The archive directory (§7.2's inherited naming) ─────────────────────────
# adopt_archive_dir_new ROOT — a fresh `<UTC-timestamp>-<pid>` directory name,
# relative to ROOT, with the precedent's `-1`, `-2`, … collision loop.
#
# The loop is not decoration. Two adoptions inside the same wall-clock second
# from the same shell would otherwise collide, and the SECOND one would write
# its MANIFEST over the first — destroying the only copy of a set of files
# whose whole purpose is to be recoverable. It is asserted by CALLING this
# function twice, because `-1` in the source proves nothing about what runs.
#
# RETENTION IS UNLIMITED, and that is §7.2's second declared divergence from
# the precedent, which prunes to keep-3. An adoption archive is written once
# per project and is the operator's only copy of their own configuration.
# Nothing in this file deletes one, on any path, including the failure paths.
adopt_archive_dir_new() {
  local root="$1" ts dir n
  ts="$(date -u +"%Y-%m-%dT%H-%M-%SZ")"
  dir=".claude/adoption-archive/$ts-$$"
  n=0
  while [ -e "$root/$dir" ]; do
    n=$((n + 1))
    dir=".claude/adoption-archive/$ts-$$-$n"
  done
  printf '%s\n' "$dir"
}

# ── The hook description (§7.2), and why it is a CLOSED vocabulary ──────────
#
# §7.2 requires a what-it-did description for every archived git hook and calls
# it explicitly ADVISORY. §7.3 names the hazard in the same breath: a
# hand-rolled hook can contain a token. So the description is ASSEMBLED FROM A
# FIXED LIST — the generator emits names it recognises and nothing else. A hook
# line reading `export AWS_ACCESS_KEY_ID=AKIA…` contributes exactly nothing,
# because no allowlisted token matches it.
#
# This is the same shape as the §6.2 field allowlist and the same shape as
# Scout's own hook vocabulary, and it is DUPLICATED here rather than sourced:
# Scout is a separate severable module under M1/M3, and reaching into
# scripts/lib/scout/ from here would fuse two modules that are meant to be
# liftable independently. §3.3 calls this reuse-by-extraction — copy the
# PREDICATE, not the DEPENDENCY — and this is exactly that case.
_adopt_archive_hook_vocabulary() {
  cat <<'VOCAB'
husky
lefthook
pre-commit
lint-staged
commitlint
gitleaks
semgrep
trufflehog
shellcheck
shfmt
npx
npm
pnpm
yarn
bun
node
deno
tsc
eslint
prettier
jest
vitest
mocha
python
python3
pytest
pip
poetry
uv
black
ruff
mypy
flake8
isort
cargo
clippy
rustfmt
go
gofmt
golangci-lint
make
gradle
mvn
dotnet
php
composer
bundle
rspec
rubocop
swiftlint
ktlint
detekt
clang-format
terraform
tflint
docker
VOCAB
}

# adopt_archive_hook_description FILE — a one-sentence advisory summary.
#
# Shallow and static by design: it reads word-shaped tokens, keeps the ones on
# the list, and says "and other commands" when it dropped something. It never
# quotes a byte of the file, so it cannot leak one.
#
# THE LOOKUP IS A `case`, NOT A PIPE INTO `grep -q`, AND THAT IS A CORRECTNESS
# FIX RATHER THAN A TIDY-UP. The driver runs under `set -o pipefail`. The
# obvious spelling —
#
#     printf '%s\n' "$(_adopt_archive_hook_vocabulary)" | grep -qx -- "$tok"
#
# — makes `grep -q` exit the moment it matches, which closes the pipe under
# `printf` and kills it with SIGPIPE (141). Under `pipefail` the PIPELINE's
# status is that 141, so a SUCCESSFUL match reports failure and the token is
# discarded as unrecognised. Whether printf has finished writing before grep
# leaves is a RACE, so the same hook described the same file three different
# ways across three runs of the same suite — and the two words nearest the top
# of the vocabulary lost most often, because grep reaches them soonest. A6's
# positive control caught it only because it looks for a specific tool name; a
# "the description is non-empty" assertion would have passed every time.
#
# THE EXACT BOUNDARY, MEASURED, BECAUSE IT DECIDES WHAT A FUTURE EDITOR MAY DO.
# The race needs a producer that writes MORE THAN ONCE. With a SINGLE `write(2)`
# — one `printf` of a whole table — it is impossible rather than merely
# unlikely: grep cannot match, and therefore cannot exit, before the producer's
# only write has completed, and after it there is nothing left to SIGPIPE.
# 3000 iterations of the single-write form: zero failures. A per-LINE writer
# under the identical pipeline: 300 failures in 300. So the hazard is not the
# `| grep -q` idiom by itself — it is the idiom plus a multi-write producer,
# which a table grown past the single-write chunk (~4KiB stdio worst case) also
# becomes. **The guard this note exists for: do not "tidy" a producer here into
# per-line emission, and do not let the vocabulary grow past a single write
# while a pipeline consumes it.** The `case` form below has neither exposure,
# which is why it is the form that ships.
adopt_archive_hook_description() {
  local f="$1" tok seen="" pretty="" others=0 vocab
  [ -f "$f" ] || { printf 'An empty or unreadable hook.'; return 0; }
  vocab=" $(_adopt_archive_hook_vocabulary | tr '\n' ' ') "
  # Split on anything that is not a word character, so `npx lint-staged` and
  # `npm run test` both surrender their tool names, and a quoted secret
  # surrenders nothing that is on the list.
  #
  # THE RENDERED SENTENCE IS BUILT IN THIS LOOP AND NEVER RE-SPLIT. The obvious
  # spelling collects the kept tokens into a space-joined string and then walks
  # it with `for t in $kept`, which depends on IFS still holding a space —
  # and it does not: measured here, after a `while IFS= read` loop the
  # subsequent unquoted expansion did not split at all, so every hook was
  # described as one token named "lint-staged npx". Nothing downstream would
  # have caught that; A6's positive control did, because it looks for a tool
  # name rather than for a non-empty string. `seen` stays space-joined because
  # `case` PATTERN-MATCHES it and never splits it.
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    case "$vocab" in
      *" $tok "*)
        case " $seen " in
          *" $tok "*) : ;;
          *) seen="$seen $tok"; pretty="$pretty \`$tok\`," ;;
        esac
        ;;
      *) others=1 ;;
    esac
  done <<TOKENS
$(tr -c 'A-Za-z0-9_-' '\n' < "$f" 2>/dev/null | grep -v '^$' | LC_ALL=C sort -u)
TOKENS
  if [ -z "$pretty" ]; then
    printf 'Ran commands this summary does not recognise. Read the archived copy.'
    return 0
  fi
  printf 'Ran%s' "$pretty"
  if [ "$others" -eq 1 ]; then
    printf ' and other commands.'
  else
    printf ' and nothing else this summary recognises.'
  fi
  return 0
}

# ── §7.3's scan (§6.2's projection) ─────────────────────────────────────────
# adopt_archive_scan ARCHIVE_ABS WORK — look at the archive BEFORE it is
# staged. Writes into WORK:
#
#   arcstatus  scanned | tool-unavailable | scan-failed
#   arccount   the finding count, or empty when nothing was scanned
#   archits    one archived-relative path per matched file, deduplicated
#   arcnote    an honest one-line explanation of whichever status it is
#
# THE STATUS VOCABULARY IS THREE WORDS BECAUSE THE CLAIMS ARE DIFFERENT, and
# collapsing any two of them into "no findings" is the silent-success class
# aimed at the one surface in this package where being wrong means a committed
# credential. `scanned` with zero findings is a positive result;
# `tool-unavailable` is nobody looked; `scan-failed` is we looked and something
# broke. Only the first may result in a commit.
adopt_archive_scan() {
  local arc="$1" work="$2"
  local _bin _rc _count

  : > "$work/archits"
  : > "$work/arccount"

  # SOIF_ADOPT_GITLEAKS_BIN exists so the suite can point this at a name that
  # is not installed and prove the tool-unavailable arm without uninstalling
  # anything on the host running the tests.
  _bin="${SOIF_ADOPT_GITLEAKS_BIN:-gitleaks}"

  if ! command -v "$_bin" >/dev/null 2>&1; then
    printf 'tool-unavailable\n' > "$work/arcstatus"
    printf '%s\n' "gitleaks is not installed, so NOTHING WAS SCANNED. That is not a clean result — it is the absence of one, and the archive is therefore NOT committed. Install it (macOS: brew install gitleaks) and re-run, or commit the archive yourself once you have checked it." > "$work/arcnote"
    return 0
  fi

  # `--exit-code 0` makes "leaks were found" an rc of 0, so a NON-zero rc means
  # the scan itself failed and can be reported as such. Without it, findings
  # and failures share an exit code and the three honest statuses collapse into
  # two. `--redact` is defence in depth and is NOT what makes this safe — the
  # three-field read below is.
  # THE SCAN'S ENVIRONMENT IS SCRUBBED, AND THIS IS A SUPPRESSION VECTOR RATHER
  # THAN A TIDY-UP (R-WP6-9). `GITLEAKS_CONFIG` and `GITLEAKS_CONFIG_TOML`
  # OUTRANK the scanned path, so the "the archive directory structurally cannot
  # contain a .gitleaks.toml" argument — which is true, and is why a repo-local
  # config cannot reach this scan — does not cover them. Measured on 8.30.1:
  # exporting either one at a config whose rules match nothing takes the same
  # planted key from 1 finding to 0, while the MANIFEST still says
  # `status: scanned`. A shell profile, a CI job env or a direnv file in the
  # adoptee would therefore have switched §7.3's refusal off silently. Unset
  # inside the subshell so the driver's own environment is untouched.
  ( cd "$arc" 2>/dev/null || exit 2
    unset GITLEAKS_CONFIG GITLEAKS_CONFIG_TOML
    "$_bin" dir --no-banner --redact --exit-code 0 -f json -r "$work/arc-gl.json" . ) \
    >"$work/arc-gl.out" 2>"$work/arc-gl.err"
  _rc=$?

  if [ "$_rc" -ne 0 ] || [ ! -f "$work/arc-gl.json" ]; then
    printf 'scan-failed\n' > "$work/arcstatus"
    printf '%s\n' "The archive's secret scan did not complete (gitleaks exited $_rc). NOTHING here was checked, so the archive is NOT committed — treat it as unknown, not as clean." > "$work/arcnote"
    return 0
  fi

  # THE PROJECTION. Three fields are NAMED and nothing else can be read: `File`
  # to know which entry to withhold, `RuleID` and `StartLine` so the operator
  # can be told where to look. `Secret`, `Match` and above all `Message` are
  # not named, so no code path exists from them to any byte written here. This
  # is one line on purpose — it is the mutation target, and replacing it with
  # the tool's own field list is what a passthrough would look like.
  if ! jq -r '.[] | [.File, .RuleID, .StartLine] | @tsv' "$work/arc-gl.json" > "$work/arc-fields" 2>/dev/null; then   # BF-ADOPT-ARCHIVE-PROJECT
    printf 'scan-failed\n' > "$work/arcstatus"
    printf '%s\n' "The scanner exited cleanly but its report did not parse, so nothing here can be trusted — the archive is NOT committed. A truncated report is usually a full disk or a killed process; re-run." > "$work/arcnote"
    return 0
  fi

  # gitleaks reports paths relative to the directory it scanned, sometimes with
  # a leading `./`. Normalise so the join against the MANIFEST's archivedPath
  # is exact rather than nearly.
  sed -e 's|^\./||' < "$work/arc-fields" | cut -f1 | grep -v '^$' | LC_ALL=C sort -u > "$work/archits"
  _count=$(grep -c '' < "$work/arc-fields" 2>/dev/null)
  case "$_count" in ''|*[!0-9]*) _count=0 ;; esac
  printf '%s\n' "$_count" > "$work/arccount"
  printf 'scanned\n' > "$work/arcstatus"
  printf '%s\n' "Every file in this archive was scanned for credentials before anything was committed. Findings are located by rule, file and line — the value itself is never recorded here." > "$work/arcnote"
  return 0
}

# ── The audit row (§8.9) ────────────────────────────────────────────────────
# adopt_audit_event ROOT EVENT DETAILS_JSON — one `adoption_event` row.
#
# §8.9 chooses ONE type with a `details.event` discriminator over five types,
# because one enum member is one five-surface change and five members is five.
# The five events the design names are:
#
#   adoption               the adoption itself                    (WP7 owns it)
#   blocker_acceptance     every accepted blocker                 (WP5 owns it)
#   secrets_disposition    every `accepted risk` disposition      (unowned)
#   collision_archive      every collision archive                THIS PACKAGE
#   collision_re_add       every re-add                           THIS PACKAGE
#
# The two this package owns are emitted; the other three have no emitter yet
# and this comment says so rather than leaving a reader to infer that adoption
# records everything already.
#
# `enforcement_level_at_event` IS "n/a" AND THAT IS A DECISION. The documented
# enum admits it, and the alternative is worse: reading the tier here would
# fork the `# BL-084-TIER-KEY` predicate into a sixth site, and CLAUDE.md's own
# gotcha list says that predicate lives in scripts that must be changed IN
# SYNC. These rows record a disclosure event, not a gate outcome; there is no
# tier for them to have been decided at.
adopt_audit_event() {
  local root="$1" event="$2" details="${3:-\{\}}"
  local _ae_type _ts row
  _ae_type="adoption_event"   # BF-ADOPT-AUDIT-ROW
  command -v jq >/dev/null 2>&1 || return 1
  _ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  row="$(jq -n --arg t "$_ae_type" --arg ts "$_ts" --arg e "$event" --argjson d "$details" \
    '{timestamp: $ts, session_id: null, type: $t, actor: "framework",
      enforcement_level_at_event: "n/a",
      details: ($d + {event: $e}),
      user_response: "n/a", final_outcome: "recorded_only"}' 2>/dev/null)"
  [ -n "$row" ] || return 1
  # EVERY FAILURE PATH RETURNS NON-ZERO (R-WP6-4). This function used to answer
  # 0 unconditionally — missing jq, an unrenderable row, and a REFUSED APPEND
  # all reported success. `bypass_audit_append` genuinely returns 1: its jq
  # filter fails on a corrupt ledger, and it gives up after a 10s lock timeout.
  # A caller that treats "recorded" as a precondition cannot do so against a
  # function that never says no, and the re-add path below is exactly such a
  # caller — so this rc is load-bearing, not tidiness.
  bypass_audit_append "$root" "$row" >/dev/null 2>&1 || return 1
  return 0
}

# _adopt_original_is_ignored ROOT REL — does the operator's own .gitignore
# cover the ORIGINAL file, in a way git would actually act on?
#
# ⚠ THE `.git/` EXEMPTION, AND THE CLAIM IT REPLACES (R-WP6-10). An earlier cut
# of this file asserted, and `docs/adoption.md` repeated, that "`.git/hooks/*`
# is NOT reported as ignored because git excludes `.git/` by construction".
# THAT IS FALSE, and it was verified false by measurement:
#
#     .gitignore = '*'        -> check-ignore .git/hooks/pre-commit  rc 0
#     .gitignore = 'hooks/'   -> rc 0   (.gitignore:1:hooks/)
#     .gitignore = '.git/'    -> rc 0   (.gitignore:1:.git/)
#     .gitignore = '.claude/settings.local.json' -> rc 1
#
# `git check-ignore` applies patterns to ANY pathname it is handed, `.git/`
# paths included; there is no check-ignore exemption for them, only a
# tracked-file one. The rc 1 originally observed was a property of the ANCHORED
# PATTERN in the fixture, not of git — and the test that "pinned the bound"
# used only that pattern, so it could not have seen the difference. A bound
# claim, a comment and a manual page were all wrong together.
#
# WHY THE EXEMPTION IS STILL RIGHT, on the corrected reasoning: the arm above
# exists to honour an operator INSTRUCTION about content. A gitignore statement
# about a `.git/` path is not an instruction git can honour — git never tracks
# `.git/`, so the rule changes nothing about git's own behaviour and expresses
# no decision about whether that content may be preserved. The "content, not
# path" doctrine has nothing to anchor to there. Without this guard a single
# cargo-cult `.git/` line — inert against every framework-written path, and
# common in real repositories — silently withholds the hooks, which are §7.3's
# carrier and the archive's entire purpose, while adoption reports success and
# the disclosure attributes to the operator an instruction git would never act
# on. Measured end to end before the fix: rc 0, hooks `original-gitignored`,
# zero hook copies in HEAD, every suite row green.
#
# G1b pins it against a rule that genuinely reaches (asserting the probe reaches
# first, so the case cannot silently revert to testing the anchored rule), and
# G1c mutates the guard away and watches the hooks disappear.
_adopt_original_is_ignored() {
  local root="$1" rel="$2"
  case "$rel" in .git/*) return 1 ;; esac   # BF-ADOPT-GITDIR-EXEMPT
  ( cd "$root" && git check-ignore -q -- "$rel" ) 2>/dev/null
}

# ── Writing the archive ─────────────────────────────────────────────────────
# adopt_archive_write ROOT WORK — inventory, copy, scan, MANIFEST, disclose,
# and record only the entries that may be committed.
#
# ORDER IS THE WHOLE DESIGN: copy, then SCAN, then decide what is staged. The
# scan cannot precede the copy — there is nothing to scan — and the staging
# decision cannot precede the scan, which is §7.3's entire sentence.
#
# RETURNS 0 EVEN WHEN IT WITHHOLDS EVERYTHING. A withheld archive is not a
# failed adoption: the operator's files are on disk, disclosed, and restorable.
# Refusing the whole run because a hook had a token in it would punish them for
# the thing the framework is trying to tell them about.
ADOPT_ARCHIVE_DIR=""
ADOPT_ARCHIVE_ENTRIES=0

adopt_archive_write() {
  local root="$1" work="$2"
  local rel class arel n=0 mode sha desc dispo staged reason
  local arc_rel arc_abs status count note first

  ADOPT_ARCHIVE_DIR=""
  ADOPT_ARCHIVE_ENTRIES=0

  adopt_archive_inventory "$root" > "$work/arcinv" || return 0
  n=$(grep -c '' < "$work/arcinv" 2>/dev/null)
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  if [ "$n" -eq 0 ]; then
    adopt_head "Your own configuration"
    adopt_note "You had none of the files the framework would otherwise land on, so nothing"
    adopt_note "was archived and nothing of yours was touched."
    return 0
  fi

  arc_rel="$(adopt_archive_dir_new "$root")"
  arc_abs="$root/$arc_rel"
  # BL-225-TOUCHED-DISK, raised BEFORE the mkdir rather than after it: a
  # `mkdir -p` that creates the parents and then fails has still changed the
  # tree, and the copy loop below runs ~110 lines before adopt_record_write, so
  # the ledger is empty through the whole copy phase while these files exist.
  adopt_touched_disk
  mkdir -p "$arc_abs" 2>/dev/null || { adopt_refuse "could not create the collision archive at $arc_rel"; return 1; }

  while IFS="$(printf '\t')" read -r rel class arel; do
    [ -n "$rel" ] || continue
    mkdir -p "$(dirname "$arc_abs/$arel")" 2>/dev/null || { adopt_refuse "could not create the archive path for $rel"; return 1; }
    # `cp -p` preserves the mode, which matters more here than anywhere else in
    # the driver: a git hook that comes back at 0644 does not run, and an
    # operator restoring one would get silence rather than an error.
    adopt_touched_disk   # BL-225-TOUCHED-DISK
    cp -p "$root/$rel" "$arc_abs/$arel" 2>/dev/null || { adopt_refuse "could not archive $rel"; return 1; }
  done < "$work/arcinv"

  # ── §7.3: LOOK BEFORE ANYTHING IS STAGED ─────────────────────────────────
  adopt_archive_scan "$arc_abs" "$work"   # BF-ADOPT-ARCHIVE-SCAN
  status="$(cat "$work/arcstatus" 2>/dev/null)"
  count="$(cat "$work/arccount" 2>/dev/null)"
  note="$(cat "$work/arcnote" 2>/dev/null)"

  # ── The MANIFEST ─────────────────────────────────────────────────────────
  : > "$work/arcentries"
  while IFS="$(printf '\t')" read -r rel class arel; do
    [ -n "$rel" ] || continue
    mode="$(stat -c '%a' "$arc_abs/$arel" 2>/dev/null || stat -f '%Lp' "$arc_abs/$arel" 2>/dev/null || printf '644')"
    sha="$(adopt_sha256 "$arc_abs/$arel")"
    desc=""
    [ "$class" = "git-hook" ] && desc="$(adopt_archive_hook_description "$arc_abs/$arel")"

    # WHAT HAPPENED TO THEIR ORIGINAL, said per entry rather than in one
    # sentence for the whole archive, because it differs per entry and a
    # blanket claim would be wrong for most of them. `composed` is §7.1's
    # marker-composed bucket: the framework appends a MARKED block to their
    # commit-msg hook, so their file keeps working and the archive is the
    # pre-composition copy the restore line puts back.
    # `APPROVAL_LOG.md` is REPLACED, not kept: A4 renders the tier-matched
    # template over it, and `kept` — "the operator's original is still at the
    # path" — would be false in the document an auditor reads to learn what
    # happened to their files.
    #
    # THIS FIELD IS FORWARD-LOOKING, AND SAYING SO IS THE POINT. The MANIFEST is
    # written at the archive stage, two steps before the state loop, so on a run
    # interrupted between them the original IS still at the path while this says
    # `replaced`. Review raised that as the value being wrong. It is not wrong;
    # it is the same tense every neighbouring field already uses — MEASURED on
    # `SOIF_ADOPT_HALT_AFTER=install`, the identical row reads
    # `{"disposition":"replaced","stagedForCommit":true}` with no commit having
    # happened. Re-deriving one field after the fact while its neighbours stay
    # declarative would make the record less coherent, not more. What the record
    # states is what this adoption WILL do to each file; an interrupted run
    # leaves every such statement unfulfilled together.
    case "$rel" in
      .git/hooks/commit-msg) dispo="composed" ;;
      APPROVAL_LOG.md)       dispo="replaced" ;;   # BL-242-ARCHIVE-DISPO
      *)                     dispo="kept" ;;
    esac

    # ── THE WITHHOLD CHAIN, IN PRECEDENCE ORDER ────────────────────────────
    #
    # Ordered by how strong the statement is, so the MANIFEST names the most
    # important reason when more than one applies: nothing was checked, then a
    # scanner match, then the operator's own instruction, then the mechanical
    # `git add` guard.
    staged="true"; reason=""
    if [ "$status" != "scanned" ]; then
      staged="false"; reason="not-scanned"
    elif grep -qxF -- "$arel" "$work/archits" 2>/dev/null; then
      staged="false"; reason="secret-match"
    elif _adopt_original_is_ignored "$root" "$rel"; then   # BF-ADOPT-IGNORE-ORIGINAL
      # A GITIGNORE ENTRY IS THE OPERATOR'S EXPLICIT STATEMENT THAT THIS
      # CONTENT MUST NEVER ENTER HISTORY (R-WP6-1). Copying it to a new path
      # and re-asking the question about the NEW path answers a question
      # nobody asked — and answers it wrongly, because the ecosystem-standard
      # rule is ANCHORED: `.claude/settings.local.json` matches the original
      # and cannot match `.claude/adoption-archive/<dir>/.claude/settings.local.json`.
      # Measured hermetically: original -> ignored, archive copy -> NOT
      # ignored. Before this arm the archive committed a copy of a gitignored
      # `settings.local.json` — the MODAL adoptee shape, and the one file most
      # likely to hold an internal hostname, a proxy URL or a username. None
      # of those is secret-SHAPED, so the scanner is no defence: G1 asserts
      # findingCount == 0 precisely to prove the ignore rule is what saved it.
      #
      # The `.git/` bound lives in the helper, with the measurement that
      # corrected it.
      staged="false"; reason="original-gitignored"
    elif ( cd "$root" && git check-ignore -q -- "$arc_rel/$arel" ) 2>/dev/null; then   # BF-ADOPT-IGNORE-ARCHIVE
      # The MECHANICAL guard, and a different question from the one above:
      # `git add` on an ignored path FAILS, and the driver stages every
      # recorded path in ONE command — so a single ignored archive entry would
      # abort the whole adoption commit. Withholding keeps the operator's
      # rules intact AND keeps the run alive, and the MANIFEST says which
      # entry and why instead of leaving them a git error to decode.
      staged="false"; reason="gitignored"
    fi

    jq -n --arg op "$rel" --arg ap "$arel" --arg cl "$class" --arg sh "$sha" \
          --arg mo "$mode" --arg de "$desc" --arg di "$dispo" \
          --argjson st "$staged" --arg re "$reason" --arg ad "$arc_rel" \
      '{originalPath: $op, archivedPath: $ap, class: $cl, sha256: $sh, mode: $mo,
        disposition: $di, description: $de,
        stagedForCommit: $st, withheldReason: $re,
        restore: ("cp " + $ad + "/" + $ap + " " + $op + " && chmod " + $mo + " " + $op)}' \
      >> "$work/arcentries" 2>/dev/null
  done < "$work/arcinv"

  jq -s --arg at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" --arg ad "$arc_rel" \
        --arg st "$status" --arg no "$note" --arg ct "$count" \
    '{schemaVersion: 1, adoptedAt: $at, archiveDir: $ad,
      advisory: "Every `description` below is a SHALLOW STATIC SUMMARY assembled from a fixed list of tool names — it is advisory, not a specification. A hook can do anything; read the archived copy before you trust the sentence.",
      secretsScan: {tool: "gitleaks", status: $st,
                    findingCount: (if $ct == "" then null else ($ct | tonumber) end),
                    note: $no},
      entries: .}' "$work/arcentries" > "$arc_abs/MANIFEST.json" 2>/dev/null \
    || { adopt_refuse "could not write the archive MANIFEST"; return 1; }

  _adopt_archive_manifest_md "$arc_abs/MANIFEST.json" > "$arc_abs/MANIFEST.md" 2>/dev/null \
    || { adopt_refuse "could not write the archive MANIFEST.md"; return 1; }

  ADOPT_ARCHIVE_DIR="$arc_rel"
  ADOPT_ARCHIVE_ENTRIES=$(jq -r '.entries | length' "$arc_abs/MANIFEST.json" 2>/dev/null)
  case "$ADOPT_ARCHIVE_ENTRIES" in ''|*[!0-9]*) ADOPT_ARCHIVE_ENTRIES=0 ;; esac

  # THE MANIFEST CARRIES NO FILE BYTES — only paths, hashes, modes and rule
  # names — so it is committed wherever it can be. It is the record of what was
  # withheld as much as of what was kept.
  #
  # BUT IT GOES THROUGH THE IGNORE GUARD LIKE EVERYTHING ELSE. An earlier cut
  # recorded both MANIFESTs unconditionally, and an operator who gitignores
  # `.claude/adoption-archive/` — an entirely reasonable thing to do to a local
  # backup directory — then hit `git add` refusing an ignored path, which took
  # THE WHOLE ADOPTION down (measured: rc 1, no adoption commit). Two arms
  # guarding the entries and one unconditional pair beside them is not a guard.
  _adopt_record_if_stageable "$root" "$arc_rel/MANIFEST.json"
  _adopt_record_if_stageable "$root" "$arc_rel/MANIFEST.md"
  while IFS= read -r arel; do
    [ -n "$arel" ] || continue
    adopt_record_write "$arc_rel/$arel"
  done <<STAGEABLE
$(jq -r '.entries[] | select(.stagedForCommit == true) | .archivedPath' "$arc_abs/MANIFEST.json" 2>/dev/null)
STAGEABLE

  _adopt_archive_disclose "$root" "$arc_rel" "$arc_abs/MANIFEST.json"

  # §8.9: "every collision archive" is one of the five events.
  #
  # THE rc IS CHECKED HERE TOO (R-WP6-11), and the asymmetry with the re-add is
  # deliberate rather than an oversight — which is why it is written down on
  # BOTH sides now instead of only on the re-add's. The re-add REFUSES when the
  # row cannot be written, because the row is the re-add's ONLY record and an
  # unrecorded override is the thing §7.3 forbids. The archive does NOT refuse,
  # because it has a primary committed record — the MANIFEST — so a failed row
  # degrades the trail rather than invalidating the act. What it must never do
  # is degrade QUIETLY. Measured before this fix, with a ledger that was already
  # corrupt when adoption started: rc 0, the row silently dropped, no mention
  # anywhere in the transcript, and THE STILL-CORRUPT LEDGER COMMITTED INTO HEAD
  # as the project's first governance record.
  if adopt_audit_event "$root" "collision_archive" \
       "$(jq -n --arg d "$arc_rel" --argjson n "$ADOPT_ARCHIVE_ENTRIES" --arg s "$status" \
           '{archiveDir: $d, entryCount: $n, secretsScanStatus: $s}' 2>/dev/null)"; then
    # AND THE LEDGER ITSELF IS COMMITTED, because this is the first row an
    # adopted project ever has. docs/audit-log-lifecycle.md draws a deliberate
    # line between the TRACKED ledger and the non-tracked
    # `.claude/last-gate-pass.txt` receipt, and a scaffolded project gets the
    # tracked side by way of init's blanket add. An adopted project stages only
    # what the driver wrote, so without this the governance record would sit
    # untracked — the archive row would exist and no clone would carry it.
    #
    # ONLY ON SUCCESS. Staging on the failure path would commit whatever
    # unparseable bytes are there — turning a corrupt file into the permanent
    # first entry of the project's audit history.
    #
    # ⚠ THE REASON THIS IS SAFE IS NOT THE ONE ORIGINALLY WRITTEN HERE
    # (R-WP6-14). That comment said "a successful append proves the ledger
    # parsed, since the appender's own jq had to read it". REFUTED by
    # measurement: `jq FILTER file` over a ZERO-BYTE file runs across zero
    # documents, emits nothing and EXITS 0 — the append succeeded, read no
    # document, and wrote no row. Measured end to end at that commit: adopt
    # rc 0, zero "could not be recorded" in the transcript, the row lost, and
    # the zero-byte ledger COMMITTED into HEAD. Same hole via `[]\n[]`, which
    # exits 0 and duplicates the row into each document.
    #
    # An exit code is not a receipt. "jq exited 0" and "jq read a document" are
    # different facts. What makes this safe now is an explicit predicate in
    # `bypass_audit_append` — `jq -es 'length == 1 and (.[0] | type ==
    # "array")'` — which rejects empty, null, multi-document and non-array
    # ledgers before the append and routes them all into the failure arm below.
    # The guard lives in the appender because six files call it and two of them
    # already announce its rc; a guard here would have fixed one caller.
    _adopt_record_if_stageable "$root" ".claude/bypass-audit.json"
  else
    adopt_blank
    adopt_say "   THE ARCHIVE HAPPENED. THE AUDIT ROW FOR IT could not be recorded."
    adopt_note "$arc_rel is written, disclosed above, and listed in its own MANIFEST — none of"
    adopt_note "that is in doubt. What is missing is the line in .claude/bypass-audit.json that"
    adopt_note "would let someone find it later without being told. The ledger would not accept"
    adopt_note "the row; it is most likely not valid JSON. It has been LEFT OUT of the commit"
    adopt_note "rather than committed in that state — check it by hand:"
    adopt_note "  jq . .claude/bypass-audit.json"
  fi
  return 0
}

# _adopt_record_if_stageable ROOT REL — record REL for staging unless the
# operator's own .gitignore excludes it.
#
# `git add` on an ignored path FAILS, and the driver stages every recorded path
# in ONE command, so a single ignored entry aborts the whole adoption commit.
# Their ignore rules are theirs; the run says what it skipped rather than
# forcing the add or dying on it.
_adopt_record_if_stageable() {
  local root="$1" rel="$2"
  [ -e "$root/$rel" ] || return 0
  # BL-225-ORACLE-SYNC: `git add --dry-run`, not `git check-ignore`. The same
  # oracle error BL-225 fixed one directory over lived here too, and it is a
  # WRONG ANSWER rather than the rc-128 fail-open below it: check-ignore is
  # index-aware and reports nothing for a TRACKED path, so a tracked
  # `.claude/bypass-audit.json` under a later-added `.claude/` rule was recorded
  # for staging — withholding nothing, disclosing nothing — and `git add` then
  # refused it. Two contradictory oracles ten files apart is how the next reader
  # copies the refuted one.
  if ! ( cd "$root" && git add --dry-run -- "$rel" ) >/dev/null 2>&1; then
    # BL-225-ORACLE-SYNC (second half): `git add --dry-run` fails for ANY
    # reason, not only an ignore rule — an unreadable file fails it too. Ask the
    # namer whether an ignore rule is actually the cause before naming one; the
    # first draft of this arm attributed every failure to `.gitignore`, which is
    # a broken install disclosed with the wrong reason.
    if adopt_name_ignored_paths "$root" "$rel" >/dev/null 2>&1; then
      adopt_note "Your .gitignore excludes $rel, so it stays out of the commit — it is on disk."
    else
      adopt_note "git will not stage $rel, so it stays out of the commit — it is on disk. git says:"
      ( cd "$root" && git add --dry-run -- "$rel" ) 2>&1 >/dev/null | grep -v '^hint:' | sed 's/^/    /'
    fi
    return 0
  fi
  adopt_record_write "$rel"
  return 0
}

# _adopt_archive_manifest_md MANIFEST.json — the same content, for a person.
# §7.2 asks for both and they are generated from ONE source so they cannot
# disagree; a human-readable disclosure that has drifted from the machine
# record is worse than not having one.
_adopt_archive_manifest_md() {
  local mj="$1"
  printf '# What was archived, and how to get it back\n\n'
  printf 'These are copies of files you already had. They were **moved to ensure the\n'
  printf 'framework operates properly** — nothing here was deleted, and every file\n'
  printf 'below can be put back with the single command beside it.\n\n'
  printf 'Archive: `%s`\n\n' "$(jq -r '.archiveDir' "$mj" 2>/dev/null)"
  printf 'Secret scan before anything was committed: **%s**' "$(jq -r '.secretsScan.status' "$mj" 2>/dev/null)"
  printf ' (%s finding(s))\n\n' "$(jq -r '.secretsScan.findingCount // "not counted"' "$mj" 2>/dev/null)"
  printf '%s\n\n' "$(jq -r '.secretsScan.note' "$mj" 2>/dev/null)"
  printf '%s\n\n' "$(jq -r '.advisory' "$mj" 2>/dev/null)"
  printf '| Your file | Archived as | What it did | Committed? | Put it back with |\n'
  printf '|---|---|---|---|---|\n'
  jq -r '.entries[] | [.originalPath, .archivedPath,
                       (if (.description // "") == "" then "-" else .description end),
                       (if .stagedForCommit then "yes" else ("no — " + .withheldReason) end),
                       .restore]
                    | @tsv' "$mj" 2>/dev/null \
    | while IFS="$(printf '\t')" read -r op ap de st re; do
        printf '| `%s` | `%s` | %s | %s | `%s` |\n' "$op" "$ap" "$de" "$st" "$re"
      done
  printf '\n## Adding one back\n\n'
  printf 'Run the command in the last column, or let the driver record it for you:\n\n'
  printf '```\nbash /path/to/solo-orchestrator/scripts/adopt-project.sh --re-add <your file>\n```\n\n'
  printf 'The second form prints the warning and writes an audit row. Either way the\n'
  printf 'file is yours; the framework only insists that the choice is written down.\n'
  return 0
}

# _adopt_archive_disclose ROOT ARCHIVE_REL MANIFEST — §7.3's disclosure.
#
# THE SENTENCE, THE LIST, AND THE RESTORE INSTRUCTIONS. Not a summary count —
# §7.3 says "the list" in as many words, and it is right: "4 files archived"
# tells an operator nothing they can act on, and the one thing they need at
# this moment is to see their own filenames go past so they can object.
_adopt_archive_disclose() {
  local root="$1" arc="$2" mj="$3"
  local op ap st re de withheld

  adopt_head "Your own configuration has been archived"
  adopt_say "   The files below were moved to ensure the framework operates properly."
  adopt_note "Nothing was deleted. Every one of them is in $arc and can be put back."
  adopt_blank
  jq -r '.entries[] | [.originalPath, .archivedPath, (if .stagedForCommit then "committed" else ("withheld:" + .withheldReason) end), (.description // "")] | @tsv' "$mj" 2>/dev/null \
    | while IFS="$(printf '\t')" read -r op ap st de; do
        adopt_note "yours: $op"
        adopt_note "   archived as: $arc/$ap"
        [ -n "$de" ] && adopt_note "   what it did: $de"
        case "$st" in
          withheld:*) adopt_note "   NOT COMMITTED — $(printf '%s' "$st" | sed 's/^withheld://')" ;;
        esac
        adopt_note "   put it back: cp $arc/$ap $op"
      done
  adopt_blank

  withheld="$(jq -r '[.entries[] | select(.stagedForCommit == false)] | length' "$mj" 2>/dev/null)"
  case "$withheld" in ''|*[!0-9]*) withheld=0 ;; esac
  if [ "$withheld" -gt 0 ]; then
    adopt_say "   $withheld of those copies were NOT added to the commit."
    adopt_note "$(jq -r '.secretsScan.note' "$mj" 2>/dev/null)"
    adopt_note "They are still on disk in $arc — they are simply not in version control."
    if jq -e '.secretsScan.status == "scanned" and (.secretsScan.findingCount > 0)' "$mj" >/dev/null 2>&1; then
      adopt_note "A credential in a file git had never seen would have become a credential in"
      adopt_note "your history. Rotate it at the source; deleting the file does not un-leak it."
      jq -r '.entries[] | select(.withheldReason == "secret-match") | "   look at: " + .originalPath' "$mj" 2>/dev/null
    fi
    if jq -e '.secretsScan.status != "scanned"' "$mj" >/dev/null 2>&1; then
      adopt_note "NOTHING WAS SCANNED, so this is not a clean result — it is the absence of one."
    fi
    # THE OPERATOR'S OWN RULE, EXPLAINED IN THEIR TERMS. "original-gitignored"
    # is a manifest token; a person reading a transcript needs the sentence.
    if jq -e '[.entries[] | select(.withheldReason == "original-gitignored")] | length > 0' "$mj" >/dev/null 2>&1; then
      adopt_note "Some of those are files your own .gitignore says never to commit. The archive"
      adopt_note "keeps a copy so you can restore them, and does NOT commit that copy under a"
      adopt_note "different name — your rule is about the contents, not about the path."
      jq -r '.entries[] | select(.withheldReason == "original-gitignored") | "   your .gitignore covers: " + .originalPath' "$mj" 2>/dev/null
    fi
    adopt_blank
  fi
  adopt_note "The full record, including a restore line for every file, is in"
  adopt_note "$arc/MANIFEST.md (and MANIFEST.json beside it)."
  return 0
}

# ── The re-add (§7.3) ───────────────────────────────────────────────────────
# THE WARNING, NEAR-VERBATIM PER THE DESIGN. Spelled ONCE, as a constant, so
# there is a single site for a test to pin and a single site to change if Karl
# ever rewords it.
ADOPT_READD_WARNING="Personal systems may conflict with the framework — accuracy, documentation, and capabilities may be compromised."

# adopt_archive_latest ROOT — the newest archive directory, relative to ROOT.
# Newest by NAME, which is safe because the name begins with a UTC timestamp in
# a lexicographically sortable format; sorting by mtime would be defeated by a
# restore that touched the directory.
adopt_archive_latest() {
  local root="$1"
  ( cd "$root" 2>/dev/null || return 1
    find .claude/adoption-archive -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
      | LC_ALL=C sort | tail -1 )
}

# adopt_archive_readd ROOT ORIGINALPATH — put one archived file back.
#
# §7.3: "Re-adds are permitted — this is Karl's decision and it matters: the
# framework's premise is opinionated enforcement, not confiscation." So this
# never argues. It warns, it requires the operator to say yes, it restores the
# file exactly as it was, and it WRITES THE ROW.
adopt_archive_readd() {
  local root="$1" want="$2"
  local arc mj entry ap mode restored_from _readd_details _readd_recorded=1

  arc="$(adopt_archive_latest "$root")"
  if [ -z "$arc" ] || [ ! -f "$root/$arc/MANIFEST.json" ]; then
    adopt_refuse "there is no collision archive in this project — nothing to add back"
    return 1
  fi
  mj="$root/$arc/MANIFEST.json"

  # READ THE TWO FIELDS DIRECTLY. The first cut selected the whole entry with
  # `@json` and then re-parsed it with `fromjson`, which fails silently — jq's
  # `-r` had already unwrapped it, so `fromjson` was handed an object rather
  # than a string, `ap` and `mode` came back empty, and every re-add refused
  # with "listed in the MANIFEST but is not on disk". Two reads of the file is
  # cheaper than a round trip through a string.
  entry="$(jq -r --arg p "$want" '[.entries[] | select(.originalPath == $p)] | length' "$mj" 2>/dev/null)"
  case "$entry" in ''|*[!0-9]*) entry=0 ;; esac
  if [ "$entry" -eq 0 ]; then
    adopt_refuse "'$want' is not in $arc/MANIFEST.json"
    {
      echo "          What is in there:"
      jq -r '.entries[] | "            " + .originalPath' "$mj" 2>/dev/null
    } >&2
    return 1
  fi
  ap="$(jq -r --arg p "$want" 'first(.entries[] | select(.originalPath == $p) | .archivedPath) // ""' "$mj" 2>/dev/null)"
  mode="$(jq -r --arg p "$want" 'first(.entries[] | select(.originalPath == $p) | .mode) // ""' "$mj" 2>/dev/null)"
  restored_from="$root/$arc/$ap"
  if [ ! -f "$restored_from" ]; then
    adopt_refuse "$arc/$ap is listed in the MANIFEST but is not on disk"
    return 1
  fi

  adopt_head "Adding back $want"
  adopt_blank
  adopt_say "   $ADOPT_READD_WARNING"
  adopt_blank
  adopt_note "This file is yours and you may have it back. The framework's own version of"
  adopt_note "whatever it governs will not be in charge while yours is in place, and this"
  adopt_note "choice is written into the audit trail either way."
  adopt_blank

  adopt_stdin_init
  adopt_ask_choice "whether to add $want back" \
    "Do you want to put your own $want back?" \
    "Yes — put it back, and record that I chose to" \
    "No — leave it archived" || return 1
  case "$ADOPT_ANSWER" in
    Yes*) : ;;
    *)
      adopt_note "Left archived. Nothing was changed."
      return 0
      ;;
  esac

  # §7.3: "every re-add is recorded in the audit trail". THE ROW IS THE POINT.
  # A re-add nobody can find later is exactly the silent confiscation-in-
  # reverse this design refuses: the framework permits the operator to override
  # it, and asks only that the override be legible to whoever reads the ledger
  # next. Suppress the marked line and the re-add still happens — silently.
  #
  # THE RECORD IS WRITTEN BEFORE THE RESTORE, AND THAT ORDER IS THE FIX
  # (R-WP6-4). Recording afterwards made "recorded" unenforceable: on a corrupt
  # ledger or a lock timeout `bypass_audit_append` returns 1, the file had
  # already been restored, and the driver went on to print "The choice is
  # recorded in .claude/bypass-audit.json" — a false claim about the only
  # artifact the re-add's legitimacy rests on. That is the R2 mutation's
  # failure mode reachable at RUNTIME rather than by sed. Recording first makes
  # the row a PRECONDITION: no row, no re-add.
  #
  # The residual is stated rather than hidden: if the `cp` below fails, a row
  # exists for a re-add that did not happen. Over-recording is the safe
  # direction — an operator investigating a row that describes nothing loses an
  # afternoon; an override with no row is the thing §7.3 forbids — and the
  # refusal that follows a failed `cp` is loud.
  #
  # AND THE WINDOW IS EXACTLY ONE STATEMENT WIDE, WHICH IT WAS NOT (R-WP6-12).
  # The `mkdir -p` used to sit inside it too, undisclosed, so a re-add that
  # could not even create its parent directory still wrote a row claiming it
  # happened. The mkdir mutates nothing the archive governs, so it belongs
  # ABOVE the record and now runs there — which makes the residual documented
  # above the WHOLE residual rather than most of it. R5 forces that failure
  # with a regular file where a directory has to go and asserts zero rows.
  adopt_touched_disk   # BL-225-TOUCHED-DISK
  mkdir -p "$(dirname "$root/$want")" 2>/dev/null || { adopt_refuse "could not create $(dirname "$want") — nothing has been changed and nothing recorded"; return 1; }
  #
  # THE DETAILS ARE BUILT ON THEIR OWN LINE so that the emit is a COMPLETE
  # ONE-LINE STATEMENT. A marker on the last line of a multi-line continuation
  # cannot be neutered by a one-line substitution without leaving a dangling
  # `\` behind it, and a mutant that does not parse proves nothing about the
  # code — it only proves sed can break a file.
  _readd_details="$(jq -n --arg p "$want" --arg a "$arc/$ap" --arg w "$ADOPT_READD_WARNING" \
      '{path: $p, archivedPath: $a, warningShown: $w}' 2>/dev/null)"
  adopt_audit_event "$root" "collision_re_add" "$_readd_details" || _readd_recorded=0   # BF-ADOPT-READD-AUDIT
  if [ "$_readd_recorded" -eq 0 ]; then
    adopt_refuse "the re-add could not be recorded in .claude/bypass-audit.json, so it was NOT made"
    {
      echo "          Every re-add is written into the audit trail — that is the whole basis on"
      echo "          which the framework lets you override it. The ledger would not accept the"
      echo "          row (it may be corrupt, or another process may be holding it), so $want"
      echo "          has been LEFT AS IT IS rather than changed with no record of who chose it."
      echo "          Check .claude/bypass-audit.json is valid JSON, then run this again."
    } >&2
    return 1
  fi

  adopt_touched_disk   # BL-225-TOUCHED-DISK
  cp -p "$restored_from" "$root/$want" || { adopt_refuse "could not restore $want — the audit row was already written, so the ledger records an intent that did not complete"; return 1; }
  case "$mode" in ''|*[!0-7]*) : ;; *) chmod "$mode" "$root/$want" 2>/dev/null ;; esac

  adopt_blank
  adopt_note "$want is back, exactly as it was, at mode $mode."
  adopt_note "The choice is recorded in .claude/bypass-audit.json as an adoption_event."
  return 0
}

# adopt_readd_main ROOT PATH — the `--re-add` entry point.
#
# A SEPARATE ENTRY POINT AND NOT A STAGE OF `adopt_main`, because a re-add
# happens LATER — days or months after adoption, when the operator has lived
# with the framework's version and decided they want theirs back. Folding it
# into the adoption run would mean the only moment they could exercise Karl's
# "re-adds are permitted" decision was the moment they had not yet formed an
# opinion.
adopt_readd_main() {
  ADOPT_OPERATION="The re-add"   # BL-225-OPERATION: not an adoption run
  # BL-225-TOUCHED-DISK: `--re-add` is dispatched BEFORE `adopt_main`, which is
  # the only place `ADOPT_WORK` is ever assigned — so without this the marker
  # writes nowhere and `adopt_has_touched_disk` answers "nothing touched" for
  # this whole command. That regressed the audit-row contradiction one round
  # after it was fixed: the refusal said "the audit row was already written"
  # and then "nothing was written". A marker that is present, correctly placed
  # and INERT is worse than an absent one, because the guard reads it as green.
  if [ -z "${ADOPT_WORK:-}" ]; then
    ADOPT_WORK="$(mktemp -d "${TMPDIR:-/tmp}/adopt-readd.XXXXXXXX" 2>/dev/null)" || {
      echo "adopt-project: could not create a temporary working directory." >&2
      return 2
    }
    trap 'rm -rf "$ADOPT_WORK"' EXIT INT TERM
  fi
  local root="$1" want="$2"
  if ! command -v jq >/dev/null 2>&1; then
    echo "adopt-project: jq is required." >&2
    return 2
  fi
  if [ -z "$want" ]; then
    echo "adopt-project: --re-add needs the path of one of YOUR files, as it is named in" >&2
    echo "  the archive MANIFEST (for example .git/hooks/pre-commit)." >&2
    return 2
  fi
  adopt_archive_readd "$root" "$want"
}

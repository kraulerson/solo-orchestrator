#!/usr/bin/env bash
# scripts/lib/adopt/adopt-ci.sh — §7.4, the CI carve-out (WP7).
#
# SPEC: ADOPT-002-ARCH v1 §7.4, carried unchanged by v2 §7.4 — "their pipelines
# are audited, not archived, and never touched"; the framework's CI installs as
# its OWN file; SDLC-undermining workflows get loud findings; keep-or-retire is
# the operator's recorded decision. `## BL-242:` assigns it to WP7.
#
# THREE THINGS, AND ONE THING IT NEVER DOES.
#   1. AUDIT — every CI file of theirs is read for four shapes that would let
#      code around the framework's checks (the table below). Report-only.
#   2. ASK — for each file with a finding, keep or retire, before any write.
#      The answer is recorded in the Adoption Record. "Retire" is the operator's
#      intention, recorded; the driver does not carry it out.
#   3. INSTALL — the framework's CI at a FRAMEWORK-OWNED name, never the
#      canonical path: on GitLab and Bitbucket the canonical file IS the
#      project's whole pipeline, and replacing it would take their deploy
#      offline on day one.
#   NEVER — edit, move, archive or delete a CI file of theirs.
#
# THE DETECTOR IS A NET, NOT A PARSER, and it says so in its output. It greps
# for known spellings, skips comment lines, and reports the rule and the line
# NUMBER — never the line's text, because a workflow can carry a credential and
# this report is printed and committed.

# The framework-owned destination per host. Spelled once.
_adopt_ci_dest() {                                     # BL-242-CI-DEST
  case "$1" in
    github)    printf '.github/workflows/solo-gates.yml' ;;
    gitlab)    printf '.gitlab-ci-solo.yml' ;;
    bitbucket) printf 'bitbucket-pipelines.solo.yml' ;;
    *)         return 1 ;;
  esac
}

# The CI files of theirs, one relative path per line. Plain files only; the
# framework's own destination is excluded so a re-read never audits itself.
_adopt_ci_files() {
  local root="$1" f
  for f in "$root"/.github/workflows/*.yml "$root"/.github/workflows/*.yaml \
           "$root/.gitlab-ci.yml" "$root/bitbucket-pipelines.yml"; do
    [ -f "$f" ] || continue
    f="${f#"$root"/}"
    case "$f" in .github/workflows/solo-gates.yml) continue ;; esac
    printf '%s\n' "$f"
  done
}

# _adopt_ci_rules FILE — "rule<TAB>line" per finding. Comment lines are
# skipped; matching is case-insensitive.
_adopt_ci_rules() {                                    # BL-242-CI-RULES
  local f="$1"
  awk '
    { line = tolower($0) }
    line ~ /^[[:space:]]*#/ { next }
    line ~ /gh pr merge[^#]*--auto|enable-pull-request-automerge|automerge-action|auto-merge|automerge/ { print "auto-merge\t" NR }
    line ~ /git push[^#]*(--force|--force-with-lease|[[:space:]]-f([[:space:]]|$))|filter-repo|filter-branch/ { print "force-push\t" NR }
    line ~ /continue-on-error:[[:space:]]*true|allow_failure:[[:space:]]*true/ { print "check-skipping\t" NR }
    line ~ /^[[:space:]]*if:[[:space:]]*(\$\{\{[[:space:]]*)?always\(\)/ { print "check-skipping\t" NR }
    line ~ /deploy/ && !seen_deploy { seen_deploy = NR }
    line ~ /(^|[^a-z])(tags|workflow_dispatch|release):/ { gated = 1 }
    line ~ /^[[:space:]]*(on:[[:space:]]*\[?[^#]*push|push:|- push)/ { on_push = 1 }
    END { if (seen_deploy && on_push && !gated) print "deploy-on-push\t" seen_deploy }
  ' "$f" 2>/dev/null
}

# ── the audit and the question (before any write) ──────────────────────────
ADOPT_CI_DECISIONS=""
adopt_ci_audit() {                                     # BL-242-CI-AUDIT
  local root="$1" f rel n_files=0 hits
  # Scratch paths spelled with `$ADOPT_WORK` on the line, which is how
  # tests/test-bl225-staging-preflight.sh's T9 tells them from project writes.
  ADOPT_CI_DECISIONS="$ADOPT_WORK/ci-decisions.tsv"
  : > "$ADOPT_WORK/ci-decisions.tsv" || { adopt_refuse "could not open the CI audit's scratch file"; return 1; }
  adopt_head "Your CI — read, not changed"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    n_files=$((n_files + 1))
    hits="$(_adopt_ci_rules "$root/$rel")"
    [ -n "$hits" ] || continue
    adopt_blank
    adopt_say "   $rel — the framework cannot vouch for what this lets through:"
    printf '%s\n' "$hits" | while IFS="$(printf '\t')" read -r rule line; do
      case "$rule" in
        auto-merge)     adopt_say "     line $line  auto-merge — a change can merge without its checks passing" ;;
        force-push)     adopt_say "     line $line  force-push or history rewrite — it can erase what the audit trail relies on" ;;
        check-skipping) adopt_say "     line $line  a failing step is allowed to pass — a red check can come out green" ;;
        deploy-on-push) adopt_say "     line $line  deploys on a branch push — code can reach production without the release phase" ;;
      esac
    done
    adopt_ask_choice "what happens to $rel" "Keep $rel as it is, or will you retire it?" \
      "Keep it — it stays exactly as it is" \
      "Retire it — I will remove or change it myself" || return 1
    case "$ADOPT_ANSWER" in
      Keep*)   printf '%s\t%s\tkeep\n'   "$rel" "$(printf '%s\n' "$hits" | cut -f1 | LC_ALL=C sort -u | tr '\n' ' ' | sed 's/ $//')" >> "$ADOPT_WORK/ci-decisions.tsv" ;;
      Retire*) printf '%s\t%s\tretire\n' "$rel" "$(printf '%s\n' "$hits" | cut -f1 | LC_ALL=C sort -u | tr '\n' ' ' | sed 's/ $//')" >> "$ADOPT_WORK/ci-decisions.tsv" ;;
    esac
  done <<CIFILES
$(_adopt_ci_files "$root")
CIFILES
  if [ "$n_files" -eq 0 ]; then
    adopt_note "No CI configuration of yours was found, so there was nothing to read."
  elif [ ! -s "$ADOPT_CI_DECISIONS" ]; then
    adopt_note "Read $n_files CI file(s) of yours; none matched a known way around the framework's checks."
    adopt_note "This is a search for known spellings, not a proof — a workflow can still do what it likes."
  else
    adopt_note "None of your CI files was changed. Your answers go into the Adoption Record."
  fi
  return 0
}

# ── the install (the `ci` write stage) ──────────────────────────────────────
# The template is the one `init.sh`'s generate_ci picks — the same host
# directory and the same language mapping — at a framework-owned name.
ADOPT_CI_INSTALLED=""   # what the record says: a path, or why nothing was installed
_adopt_ci_template_name() {
  case "$1" in
    typescript|javascript) printf 'typescript.yml' ;;
    python) printf 'python.yml' ;;  rust) printf 'rust.yml' ;;  csharp) printf 'csharp.yml' ;;
    kotlin) printf 'kotlin.yml' ;;  java) printf 'java.yml' ;;  go) printf 'go.yml' ;;
    dart) printf 'dart.yml' ;;      swift) printf 'swift.yml' ;;
    *) printf 'other.yml' ;;
  esac
}

adopt_write_ci() {                                     # BL-242-CI-STAGE
  local root="$1" report="$2" host lang tmpl dest out
  adopt_head "The framework's CI"
  host="$(jq -r '.host // ""' "$root/.claude/manifest.json" 2>/dev/null)"
  case "$host" in
    github|gitlab|bitbucket) ;;
    *)
      ADOPT_CI_INSTALLED="none — the project's host is '${host:-unknown}', and the framework has no CI template for it"
      adopt_note "No framework CI was laid down: no CI host was found for this project, and"
      adopt_note "init.sh lays none down for host 'other' either. Supply your own CI."
      return 0 ;;
  esac
  lang="$(adopt_report_read "$report" '.stack.languages[0].name // ""' | tr '[:upper:]' '[:lower:]')"
  tmpl="$ADOPT_FRAMEWORK_ROOT/templates/pipelines/ci/$host/$(_adopt_ci_template_name "$lang")"
  [ -f "$tmpl" ] || { adopt_refuse "the framework's CI template $tmpl is missing"; return 1; }
  dest="$(_adopt_ci_dest "$host")"
  # AN EXISTING FILE AT THE FRAMEWORK'S OWN NAME IS THEIRS: left alone and said.
  if [ -e "$root/$dest" ] || [ -L "$root/$dest" ]; then
    ADOPT_CI_INSTALLED="none — $dest already exists and was left as it is"
    adopt_note "$dest already exists in your project; it was left as it is, so the framework's"
    adopt_note "CI was NOT installed. Compare it with $tmpl."
    return 0
  fi
  out="$(_adopt_doc_put "$root" "$dest" "$tmpl")" || return 1
  case "$out" in
    kept-*)
      ADOPT_CI_INSTALLED="none — $dest sits inside a symlinked folder and was not written through"
      adopt_note "$dest was NOT written: its folder is a symlink, and writing through it could"
      adopt_note "change a file outside this project."
      return 0 ;;
  esac
  ADOPT_CI_INSTALLED="$dest"
  adopt_note "Installed the framework's CI as $dest — its own file, beside yours."
  case "$host" in
    github)
      adopt_note "GitHub runs every workflow in .github/workflows, so it runs from your next push."
      adopt_note "It may fail on code that predates adoption; that is a finding, not a breakage —"
      adopt_note "your own workflows are unchanged." ;;
    gitlab)
      adopt_say  "   IT DOES NOT RUN YET. GitLab runs only .gitlab-ci.yml. To run it, add this to yours:"
      adopt_say  "     include:"
      adopt_say  "       - local: '.gitlab-ci-solo.yml'" ;;
    bitbucket)
      adopt_say  "   IT DOES NOT RUN. Bitbucket runs only bitbucket-pipelines.yml and has no way to"
      adopt_say  "   include a second file from the same repository. Copy the steps you want from"
      adopt_say  "   bitbucket-pipelines.solo.yml into yours." ;;
  esac
  return 0
}

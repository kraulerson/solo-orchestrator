#!/usr/bin/env bash
# scripts/lib/plan-staging.sh
#
# BL-109 SLICE-S3 (Layer 2 — Staging). The `--plan` engine: it builds one dated,
# committable RUN FOLDER under docs/updates/ that stages every available framework
# update for human review + consent. It is the emission half of the Currency
# System's selection surface. It NEVER writes a live (user) artifact — every write
# is confined to the run folder (invariant I1). It applies NOTHING and prompts for
# NOTHING (consent + apply are S4). Design v1.1 §2-L2, §3 (I1/I3/I5/I11), review-r1
# B3/B4/M1/M2/M4/M8.
#
# RUN FOLDER (design v1.1 §2-L2):
#   docs/updates/<YYYY-MM-DD>_<framework-shortsha>_<hhmmss>-<pid>/
#     UPDATE-PLAN.md   human review doc + THE selection surface (checkboxes)
#     manifest.json    machine journal-of-record (S4's --apply parses UPDATE-PLAN
#                      into this; here it is the plan's own record)
#     .gitignore       gitignores incoming/ + archive/ (bulky, prunable)
#     incoming/        pristine upstream material (gitignored)   [S4 also fills]
#     diffs/           per-item unified diff + mechanical CHANGELOG roll-up
#     review/          subagent ADVISORY analyses (S4 fills) + A2 structural diffs
#     archive/         pre-apply originals (S4 fills; gitignored)
#     merged/          A1 three-way candidates (conflict markers stay here)
#     patches/         A1 patches (git apply → the candidate)
#
# ITEM VERBS (review-r1 B4): add | update | retire | rename. Retire/rename are
# ALWAYS item-consent. Hooks + gate scripts are ALWAYS item-consent with the FULL
# unified diff (I11). Class A1 stages a generator-leg three-way candidate; Class A2
# stages a structural diff ONLY (no merge, ever — review-r1 B3).
#
# MECHANICAL FACTS ONLY (review-r1 M8): class, verb, diffstat, base-sha, tier and
# the CHANGELOG roll-up are all script-computed here; no model call. The roll-up is
# `git -C <fw> log --oneline <pin>..HEAD -- <path>` when the pin is present in the
# clone, else the EXACT shallow-clone fallback line (review-r1 M1). NEVER a network
# operation during --plan.
#
# PIN-ABSENT (BL-110): a manifest with no soloFrameworkCommit still plans — it
# emits the local-edit / hook / render-base items it CAN derive plus a notice that
# framework-drift + A1 candidate staging need the pin. Never a crash.
#
# bash-3.2 safe: no associative arrays, no `[[ -v ]]`, no `((x++))` under set -e,
# no `nullglob`. Assumes the CALLER does NOT run under `set -e`. Depends on: jq,
# git (LOCAL reads only), shasum, diff, git merge-file, and the sibling libs
# currency-manifest.sh + freshness-detect.sh + scaffold-shipped-set.sh +
# render-project-docs.sh + hook-templates.sh + helpers.sh (print_*), all sourced
# by the caller framework-side.

# ── Wiring: source sibling libs if a caller has not already ──────────────────
_soif_ps_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v soif_currency_sha256 >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  [ -f "$_soif_ps_dir/currency-manifest.sh" ] && . "$_soif_ps_dir/currency-manifest.sh"
fi
if ! command -v soif_freshness_detect >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  [ -f "$_soif_ps_dir/freshness-detect.sh" ] && . "$_soif_ps_dir/freshness-detect.sh"
fi
if ! command -v soif_render_claude_md >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  [ -f "$_soif_ps_dir/render-project-docs.sh" ] && . "$_soif_ps_dir/render-project-docs.sh"
fi
unset _soif_ps_dir

# The exact review-r1 M1 shallow-clone fallback line (byte-stable — a test pins it).
SOIF_PLAN_SHALLOW_FALLBACK='history unavailable (shallow clone — git fetch --unshallow to enable)'

# ── Small primitives ─────────────────────────────────────────────────────────
_soif_plan_sha() {
  if command -v soif_currency_sha256 >/dev/null 2>&1; then
    soif_currency_sha256 "$1" 2>/dev/null
  else
    [ -f "$1" ] || return 1
    shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  fi
}

_soif_plan_short() { printf '%s' "$1" | cut -c1-12; }

# _soif_plan_base_sha <proj> <path> <verb> — the LIVE (project) file's sha256 at
# plan time (review-r1 M2: the base every apply re-verifies against). Empty for an
# `add` (there is no live file yet). One definition so the guard registry can pin
# it with a single neuter. # BL-109-PLAN-BASESHA
_soif_plan_base_sha() {
  local proj="$1" path="$2" verb="$3"
  [ "$verb" = "add" ] && { printf ''; return 0; }
  _soif_plan_sha "$proj/$path"
}

# _soif_plan_iso <epoch> — ISO-8601 UTC (GNU-first then BSD).
_soif_plan_iso() {
  date -u -d "@$1" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
    || date -u -r "$1" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
    || date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# _soif_plan_is_enforcement_path <rel> — gate scripts / hooks are ENFORCEMENT tier
# AND item-consent (I11). Mirrors freshness-detect's list exactly.
_soif_plan_is_enforcement_path() {
  if command -v _soif_fresh_is_enforcement_path >/dev/null 2>&1; then
    _soif_fresh_is_enforcement_path "$1"; return $?
  fi
  case "$1" in
    scripts/pre-commit-gate.sh|scripts/check-phase-gate.sh|scripts/check-gate.sh|\
    scripts/process-checklist.sh|scripts/run-phase3-validation.sh|\
    scripts/lib/tdd-classify.sh|scripts/lib/enforcement-level.sh|\
    scripts/lib/gate-principles.sh|scripts/lib/hook-templates.sh|\
    scripts/hooks/*) return 0 ;;
    *) return 1 ;;
  esac
}

# _soif_plan_fw_relpath <fw> <init> <rel> — the framework repo-relative path a
# tracked project rel was shipped FROM (reuses freshness-detect's mechanical map).
_soif_plan_fw_relpath() {
  local fw="$1" init="$2" rel="$3" abs
  case "$rel" in
    scripts/*|templates/generated/*) printf '%s' "$rel"; return 0 ;;
  esac
  if command -v _soif_fresh_fw_source >/dev/null 2>&1; then
    abs="$(_soif_fresh_fw_source "$fw" "$init" "$rel")"
    [ -n "$abs" ] || { printf '%s' "$rel"; return 0; }
    printf '%s' "${abs#"$fw"/}"
  else
    printf '%s' "$rel"
  fi
}

# _soif_plan_diffstat <old_or_/dev/null> <new_or_/dev/null> — "added removed".
_soif_plan_diffstat() {
  local a="$1" b="$2" added removed
  [ -f "$a" ] || a=/dev/null
  [ -f "$b" ] || b=/dev/null
  local d
  d="$(diff -u "$a" "$b" 2>/dev/null)"
  added="$(printf '%s\n' "$d" | grep -c '^+[^+]')"
  removed="$(printf '%s\n' "$d" | grep -c '^-[^-]')"
  # grep -c on empty adds a phantom; normalize
  [ -n "$added" ] || added=0
  [ -n "$removed" ] || removed=0
  printf '%s %s' "$added" "$removed"
}

# ── Framework shipped-set (for ADD detection) ────────────────────────────────
# _soif_plan_framework_shipped <fw> <init> — "rel\tclass" per shipped item.
_soif_plan_framework_shipped() {
  local fw="$1" init="$2" rel
  soif_parse_shipped_scripts "$init" "$fw/scripts" 2>/dev/null | while IFS= read -r rel; do
    [ -n "$rel" ] && printf '%s\tM\n' "$rel"; done
  soif_parse_shipped_skills "$init" "$fw/templates/generated/skills" 2>/dev/null | while IFS= read -r rel; do
    [ -n "$rel" ] && printf '%s\tM\n' "$rel"; done
  soif_parse_shipped_reference_docs "$init" 2>/dev/null | while IFS= read -r rel; do
    [ -n "$rel" ] && printf '%s\tT\n' "$rel"; done
  soif_parse_shipped_templates "$init" 2>/dev/null | while IFS= read -r rel; do
    [ -n "$rel" ] && printf '%s\tT\n' "$rel"; done
}

# ── Item derivation ──────────────────────────────────────────────────────────
# _soif_plan_derive_items — writes plan-item TSV rows to stdout:
#   id \t class \t verb \t tier \t path \t consent \t rename_of
# Reuses freshness-detect's comparison facts (never re-derives them) and adds the
# ADD verb (framework-shipped rel not in files{}) + rename linkage. Also writes the
# NON-item notices (pin-behind, local-edit, cdf) to $NOTICES_FILE as
# "kind\tmessage" lines.
_soif_plan_derive_items() {
  local proj="$1" mani="$2" fw="$3" init="$4" cdf="$5" pin_present="$6" notices="$7"
  local items_tmp; items_tmp="$(mktemp)"

  # (1) Reuse the S2 detector's union of drift facts.
  local fresh; fresh="$(soif_freshness_detect "$proj" "$mani" "$fw" "$init" "$cdf")"
  local id check tier path verb sig msg
  printf '%s\n' "$fresh" | while IFS="$(printf '\t')" read -r id check tier path verb sig msg; do
    [ -n "$id" ] || continue
    case "$check" in
      framework-drift)
        local cls consent
        cls="$(soif_currency_file_field "$mani" "$path" class)"; [ -n "$cls" ] || cls=M
        if _soif_plan_is_enforcement_path "$path"; then consent=item; else consent=batch; fi
        printf '%s\t%s\tupdate\t%s\t%s\t%s\t\n' "$id" "$cls" "$tier" "$path" "$consent" >> "$items_tmp" ;;
      orphan)
        local cls
        cls="$(soif_currency_file_field "$mani" "$path" class)"; [ -n "$cls" ] || cls=M
        printf '%s\t%s\tretire\tenforcement\t%s\titem\t\n' "$id" "$cls" "$path" >> "$items_tmp"  ;; # BL-109-PLAN-RETIRE
      render-base)
        case "$path" in
          CLAUDE.md|PROJECT_INTAKE.md)
            printf '%s\tA1\tupdate\tinformational\t%s\tbatch\t\n' "$id" "$path" >> "$items_tmp" ;;
          PROJECT_BIBLE.md|PRODUCT_MANIFESTO.md)
            printf '%s\tA2\tupdate\tinformational\t%s\titem\t\n' "$id" "$path" >> "$items_tmp" ;;
        esac ;;
      hook)
        # hook-missing/hook-unavailable → add; hook-drift → update. I11 item-consent.
        local hverb=update
        case "$id" in hook-missing:*|hook-unavailable:*) hverb=add ;; esac
        printf '%s\thook\t%s\tenforcement\t%s\titem\t\n' "$id" "$hverb" "$path" >> "$items_tmp" ;;
      local-edit)
        printf 'local-edit\t%s\n' "$msg" >> "$notices" ;;
      framework)
        printf 'framework\t%s\n' "$msg" >> "$notices" ;;
      cdf)
        printf 'cdf\t%s\n' "$msg" >> "$notices" ;;
    esac
  done

  # (2) ADD detection — framework-shipped rel not in files{} (pin-gated: adds are a
  # framework-tree comparison, held to the same pin contract as drift/orphan so the
  # pin-absent path degrades cleanly to local-edit/hook/render-base only, BL-110).
  if [ "$pin_present" = true ]; then
    local shipped rel cls tracked src consent tier
    shipped="$(_soif_plan_framework_shipped "$fw" "$init")"
    printf '%s\n' "$shipped" | while IFS="$(printf '\t')" read -r rel cls; do
      [ -n "$rel" ] || continue
      tracked="$(soif_currency_file_field "$mani" "$rel" class)"
      [ -z "$tracked" ] || continue                     # already tracked → not an add
      src="$(_soif_plan_fw_relpath "$fw" "$init" "$rel")"
      [ -f "$fw/$src" ] || continue                     # source must exist upstream
      if _soif_plan_is_enforcement_path "$rel"; then consent=item; tier=enforcement; else consent=batch; tier=informational; fi
      printf 'add:%s\t%s\tadd\t%s\t%s\t%s\t\n' "$rel" "$cls" "$tier" "$rel" "$consent" >> "$items_tmp"
    done
  fi

  # (3) RENAME linkage — a retire whose sha256 matches an add's framework sha.
  _soif_plan_link_renames "$mani" "$fw" "$init" "$items_tmp"

  cat "$items_tmp"
  rm -f "$items_tmp" 2>/dev/null || true
}

# _soif_plan_link_renames <mani> <fw> <init> <items_tmp> — rewrite retire+add pairs
# whose content sha matches into linked `rename` items (rename_of = paired id).
_soif_plan_link_renames() {
  local mani="$1" fw="$2" init="$3" items="$4"
  local rewrite; rewrite="$(mktemp)"
  local id cls verb tier path consent rof
  while IFS="$(printf '\t')" read -r id cls verb tier path consent rof; do
    [ -n "$id" ] || continue
    if [ "$verb" = "retire" ]; then
      local rsha add_id add_path
      rsha="$(soif_currency_file_field "$mani" "$path" sha256)"
      add_id=""; add_path=""
      if [ -n "$rsha" ]; then
        # find an add whose framework source sha matches
        local aid acls averb atier apath aconsent arof asrc asha
        while IFS="$(printf '\t')" read -r aid acls averb atier apath aconsent arof; do
          [ "$averb" = "add" ] || continue
          asrc="$(_soif_plan_fw_relpath "$fw" "$init" "$apath")"
          asha="$(_soif_plan_sha "$fw/$asrc")"
          if [ -n "$asha" ] && [ "$asha" = "$rsha" ]; then add_id="$aid"; add_path="$apath"; break; fi
        done < "$items"
      fi
      if [ -n "$add_id" ]; then
        printf '%s\t%s\trename\t%s\t%s\titem\t%s\n' "$id" "$cls" "$tier" "$path" "$add_id" >> "$rewrite"
      else
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$cls" "$verb" "$tier" "$path" "$consent" "$rof" >> "$rewrite"
      fi
    elif [ "$verb" = "add" ]; then
      # is this add the target of some retire's rename?
      local rid rcls rverb rtier rpath rconsent rrof rsha
      local matched=""
      while IFS="$(printf '\t')" read -r rid rcls rverb rtier rpath rconsent rrof; do
        [ "$rverb" = "retire" ] || continue
        rsha="$(soif_currency_file_field "$mani" "$rpath" sha256)"
        local msrc msha
        msrc="$(_soif_plan_fw_relpath "$fw" "$init" "$path")"
        msha="$(_soif_plan_sha "$fw/$msrc")"
        if [ -n "$msha" ] && [ "$msha" = "$rsha" ]; then matched="$rid"; break; fi
      done < "$items"
      if [ -n "$matched" ]; then
        printf '%s\t%s\trename\t%s\t%s\titem\t%s\n' "$id" "$cls" "$tier" "$path" "$matched" >> "$rewrite"
      else
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$cls" "$verb" "$tier" "$path" "$consent" "$rof" >> "$rewrite"
      fi
    else
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$cls" "$verb" "$tier" "$path" "$consent" "$rof" >> "$rewrite"
    fi
  done < "$items"
  mv "$rewrite" "$items"
}

# ── Roll-up (mechanical; review-r1 M1) ───────────────────────────────────────
# _soif_plan_rollup <fw> <pin> <pin_present> <fw_relpath> — the CHANGELOG roll-up
# for one path. Pin present AND resolvable in the clone → `git log --oneline
# <pin>..HEAD -- <path>`; else the EXACT shallow-clone fallback line. NEVER fetches.
_soif_plan_rollup() {
  local fw="$1" pin="$2" pin_present="$3" relpath="$4"
  if [ "$pin_present" = true ] && [ -n "$pin" ] \
     && git -C "$fw" cat-file -e "${pin}^{commit}" >/dev/null 2>&1; then
    local log
    log="$(git -C "$fw" log --oneline "${pin}..HEAD" -- "$relpath" 2>/dev/null)"
    if [ -n "$log" ]; then printf '%s\n' "$log"; else printf '(no commits touch this path in %s..HEAD)\n' "$(_soif_plan_short "$pin")"; fi
  else
    printf '%s\n' "$SOIF_PLAN_SHALLOW_FALLBACK"
  fi
}

# ── Class dispatch: per-item stager ──────────────────────────────────────────
# Each writes ONLY under $RUN_DIR. Returns the candidate/structural relpath (or
# empty) on stdout so the manifest + UPDATE-PLAN can reference it.

# _soif_plan_build_diff <run> <proj> <fw> <init> <pin> <pin_present> <id> <verb> <path>
#   Class M/T (+ hook diffs live in UPDATE-PLAN, not here): a unified diff
#   (framework-current vs project-current) + the mechanical roll-up. Prints the
#   diff relpath.
_soif_plan_build_diff() {
  local run="$1" proj="$2" fw="$3" init="$4" pin="$5" pin_present="$6" id="$7" verb="$8" path="$9"
  local src fw_rel base new safe
  fw_rel="$(_soif_plan_fw_relpath "$fw" "$init" "$path")"
  src="$fw/$fw_rel"
  base="$proj/$path"          # project-current
  new="$src"                  # framework-current
  safe="$(printf '%s' "$id" | tr '/:' '__')"
  local dfile="diffs/${safe}.diff"
  {
    printf '# %s  (%s / %s)\n' "$id" "$verb" "$path"
    printf '# framework path: %s\n\n' "$fw_rel"
    printf '## Unified diff (project-current → framework-current)\n\n'
    printf '```diff\n'
    case "$verb" in
      add)    diff -u /dev/null "$new" 2>/dev/null ;;
      retire) diff -u "$base" /dev/null 2>/dev/null ;;
      *)      diff -u "$base" "$new" 2>/dev/null ;;
    esac
    printf '```\n\n'
    printf '## Mechanical changelog roll-up\n\n'
    printf '```\n'
    _soif_plan_rollup "$fw" "$pin" "$pin_present" "$fw_rel"
    printf '```\n'
  } > "$run/$dfile"
  printf '%s' "$dfile"
}

# _soif_plan_build_a1_candidate <run> <proj> <fw> <pin> <pin_present> <id> <artifact>
#   Class A1: the generator-leg three-way. render-then (OLD template AT THE PIN via
#   `git show`) = base; render-now (NEW template at HEAD) = theirs; user-file-now =
#   ours. `git merge-file` → merged/<artifact>.candidate (conflict markers STAY);
#   diff user→candidate → patches/<id>.patch. Pin-absent OR the old template cannot
#   be recovered → NO candidate, a declared notice (never a template-leg merge).
#   Prints "candidate_relpath\tpatch_relpath\tstatus" (status: candidate|withheld:*).
_soif_plan_build_a1_candidate() {
  local run="$1" proj="$2" fw="$3" pin="$4" pin_present="$5" id="$6" artifact="$7"
  local tmpl userfile safe then_tmpl now_tmpl then_out now_out cand patch
  # A1 artifacts map to their render templates. The A2 artifacts (bible/manifesto)
  # are mapped too, but ONLY so the # BL-109-PLAN-A2FENCE guard-registry row can
  # OBSERVE a breach: in normal operation the class dispatch routes A2 to
  # _soif_plan_build_a2_structural and NEVER here (review-r1 B3). If a neutered
  # fence mis-routed an A2 artifact into this merge path, a merged/<A2>.candidate
  # would appear — which the A2-fence test asserts must NOT happen.
  case "$artifact" in
    CLAUDE.md)            tmpl="templates/generated/claude-md.tmpl" ;;
    PROJECT_INTAKE.md)    tmpl="templates/project-intake.md" ;;
    PROJECT_BIBLE.md)     tmpl="templates/generated/project-bible.tmpl" ;;
    PRODUCT_MANIFESTO.md) tmpl="templates/generated/product-manifesto.tmpl" ;;
    *) printf '\t\twithheld:unknown-artifact'; return 0 ;;
  esac
  userfile="$proj/$artifact"
  safe="$(printf '%s' "$artifact" | tr '/:' '__')"

  if [ ! -f "$userfile" ]; then printf '\t\twithheld:no-live-file'; return 0; fi
  if [ "$pin_present" != true ] || [ -z "$pin" ] \
     || ! git -C "$fw" cat-file -e "${pin}:${tmpl}" >/dev/null 2>&1; then
    printf '\t\twithheld:pin-absent'; return 0
  fi

  then_tmpl="$run/incoming/${safe}.template.then"
  now_tmpl="$fw/$tmpl"
  # OLD template at the pin (a run-folder write — allowed).
  git -C "$fw" show "${pin}:${tmpl}" > "$then_tmpl" 2>/dev/null || { printf '\t\twithheld:show-failed'; return 0; }

  then_out="$run/incoming/${safe}.render.then"
  now_out="$run/incoming/${safe}.render.now"
  _soif_plan_recover_and_render "$proj" "$artifact" "$then_tmpl" "$then_out"
  _soif_plan_recover_and_render "$proj" "$artifact" "$now_tmpl"  "$now_out"

  # A1 placeholder-free assertion (# BL-109-PLAN-A1PLACEHOLDER): if either render
  # leg still carries a generator placeholder (union grammar __[A-Z][A-Z_]*__ — an
  # unrecovered var or a stray template token), WITHHOLD the candidate rather than
  # risk injecting placeholder text into a merge (the I3 nightmare, review-r1 B3b).
  if _soif_plan_has_placeholder "$then_out" || _soif_plan_has_placeholder "$now_out"; then
    printf '\t\twithheld:unrendered-placeholder'; return 0
  fi

  cand="merged/${safe}.candidate"
  patch="patches/${safe}.patch"
  # three-way: ours=user-now (copied so merge-file -p leaves inputs intact), base=then, theirs=now
  cp "$userfile" "$run/incoming/${safe}.ours"
  git merge-file -p "$run/incoming/${safe}.ours" "$then_out" "$now_out" > "$run/$cand" 2>/dev/null || true
  # patch: apply to the LIVE file (a/artifact b/artifact) → the candidate.
  diff -u -L "a/$artifact" -L "b/$artifact" "$userfile" "$run/$cand" > "$run/$patch" 2>/dev/null || true
  printf '%s\t%s\tcandidate' "$cand" "$patch"
}

# _soif_plan_recover_and_render <proj> <artifact> <template> <out> — recover the
# render vars from project state and render <template> → <out> via the generator.
#
# VAR RECOVERY ORDER (documented; the three-way tolerates imperfect recovery — a
# wrong value only matters when the template change overlaps a substituted line,
# and then it surfaces as a conflict, never silent corruption):
#   PROJECT_NAME        phase-state.project → CLAUDE.md "**Project:**" → "project"
#   DESCRIPTION         CLAUDE.md "**Description:**" → intake row → ""
#   PLATFORM            tool-preferences.context.platform → CLAUDE.md → ""
#   TRACK               phase-state.track → tool-preferences.context.track → manifest → "standard"
#   LANGUAGE            tool-preferences.context.language → intake-progress.language → CLAUDE.md → ""
#   TEST_INTERVAL       CLAUDE.md "Testing interval: Every N" → "2"
#   DEPLOYMENT          phase-state.deployment → manifest.deployment → "personal"
#   DATE                tool-preferences.resolved_at → intake "**Date**" → today
_soif_plan_recover_and_render() {
  local proj="$1" artifact="$2" template="$3" out="$4"
  local ps="$proj/.claude/phase-state.json" tp="$proj/.claude/tool-preferences.json"
  local mf="$proj/.claude/manifest.json" ip="$proj/.claude/intake-progress.json"
  local cm="$proj/CLAUDE.md" ik="$proj/PROJECT_INTAKE.md"
  local name desc platform track language test_interval deployment date

  name="$(jq -r '.project // empty' "$ps" 2>/dev/null)"
  [ -n "$name" ] || name="$(_soif_plan_cmfield "$cm" 'Project')"
  [ -n "$name" ] || name="project"

  desc="$(_soif_plan_cmfield "$cm" 'Description')"

  platform="$(jq -r '.context.platform // empty' "$tp" 2>/dev/null)"
  [ -n "$platform" ] || platform="$(_soif_plan_cmfield "$cm" 'Platform')"

  track="$(jq -r '.track // empty' "$ps" 2>/dev/null)"
  [ -n "$track" ] || track="$(jq -r '.context.track // empty' "$tp" 2>/dev/null)"
  [ -n "$track" ] || track="$(jq -r '.track // empty' "$mf" 2>/dev/null)"
  [ -n "$track" ] || track="standard"

  language="$(jq -r '.context.language // empty' "$tp" 2>/dev/null)"
  [ -n "$language" ] || language="$(jq -r '.language // empty' "$ip" 2>/dev/null)"
  [ -n "$language" ] || language="$(_soif_plan_cmfield "$cm" 'Primary Language')"

  test_interval="$(grep -m1 'Testing interval:' "$cm" 2>/dev/null | sed -n 's/.*Every \([0-9][0-9]*\) features.*/\1/p')"
  [ -n "$test_interval" ] || test_interval="2"

  deployment="$(jq -r '.deployment // empty' "$ps" 2>/dev/null)"
  [ -n "$deployment" ] || deployment="$(jq -r '.deployment // empty' "$mf" 2>/dev/null)"
  [ -n "$deployment" ] || deployment="personal"

  date="$(jq -r '.resolved_at // empty' "$tp" 2>/dev/null)"
  [ -n "$date" ] || date="$(grep -m1 '| \*\*Date\*\* |' "$ik" 2>/dev/null | sed -n 's/.*| \*\*Date\*\* | \(.*\) |.*/\1/p')"
  [ -n "$date" ] || date="$(date +%Y-%m-%d)"

  case "$artifact" in
    CLAUDE.md)
      soif_render_claude_md "$template" "$out" "$name" "$desc" "$platform" "$track" "$language" "$test_interval" "$deployment" ;;
    PROJECT_INTAKE.md)
      # NO resolver output at plan time — structural render only; the user's tooling
      # summary is preserved through the three-way as ours-only trailing content.
      soif_render_project_intake "$template" "$out" "$name" "$desc" "$track" "$platform" "$deployment" "$date" ;;
    *)
      # A2 artifacts have no render vars — verbatim copy. Reachable ONLY under a
      # neutered A2 fence (see _soif_plan_build_a1_candidate); makes the breach
      # observable as a written candidate.
      cp "$template" "$out" 2>/dev/null || : ;;
  esac
}

# _soif_plan_cmfield <claude_md> <label> — value of a "- **<label>:** X" line.
_soif_plan_cmfield() {
  grep -m1 "^- \*\*$2:\*\*" "$1" 2>/dev/null | sed "s/^- \*\*$2:\*\* *//"
}

# _soif_plan_has_placeholder <file> — 0 if a generator placeholder survives. The
# union grammar is __[A-Z][A-Z_]*__ (PROJECT_NAME-class AND __DATE__); the leading
# [A-Z] excludes the intake template's legitimate user-fillable ______ blanks.
_soif_plan_has_placeholder() {
  [ -f "$1" ] || return 1
  grep -qE '__[A-Z][A-Z_]*__' "$1" 2>/dev/null
}

# _soif_plan_build_a2_structural <run> <proj> <fw> <pin> <pin_present> <id> <artifact>
#   Class A2 (agent-authored): NO merge, NO patch, EVER (review-r1 B3). Emits
#   review/<artifact>.structural.md — template-then vs template-now heading delta +
#   a presence check against the user's file — and copies the skeleton blocks of
#   any section the NEW template has but the user LACKS into incoming/ as
#   INSERT-BY-HAND material. Prints the structural relpath.
_soif_plan_build_a2_structural() {
  local run="$1" proj="$2" fw="$3" pin="$4" pin_present="$5" id="$6" artifact="$7"
  local tmpl userfile safe struct then_avail=false
  case "$artifact" in
    PROJECT_BIBLE.md)     tmpl="templates/generated/project-bible.tmpl" ;;
    PRODUCT_MANIFESTO.md) tmpl="templates/generated/product-manifesto.tmpl" ;;
    *) printf ''; return 0 ;;
  esac
  userfile="$proj/$artifact"
  safe="$(printf '%s' "$artifact" | tr '/:' '__')"
  struct="review/${safe}.structural.md"

  local now_tmpl="$fw/$tmpl" then_tmpl="$run/incoming/${safe}.template.then"
  if [ "$pin_present" = true ] && [ -n "$pin" ] \
     && git -C "$fw" show "${pin}:${tmpl}" > "$then_tmpl" 2>/dev/null; then
    then_avail=true
  fi

  # Heading sets (## / ### / #### and "Appendix" lines).
  local now_h user_h then_h
  now_h="$(_soif_plan_headings "$now_tmpl")"
  user_h="$(_soif_plan_headings "$userfile")"
  then_h=""
  [ "$then_avail" = true ] && then_h="$(_soif_plan_headings "$then_tmpl")"

  {
    printf '# A2 structural diff — %s\n\n' "$artifact"
    printf '**Class A2 (agent-authored): NO merge, NO patch — structural analysis only.**\n\n'
    printf 'This file is user prose. The updater NEVER rewrites it. Below is the\n'
    printf 'heading-level delta between the framework template and your file, plus\n'
    printf 'INSERT-BY-HAND skeletons (in `incoming/`) for sections the new template\n'
    printf 'ships that your file lacks. Decide by hand which to adopt.\n\n'
    if [ "$then_avail" = true ]; then
      printf '## Upstream template heading delta (template-then → template-now)\n\n'
      local h
      printf '%s\n' "$now_h" | while IFS= read -r h; do
        [ -n "$h" ] || continue
        if ! printf '%s\n' "$then_h" | grep -qxF "$h"; then printf -- '- ADDED upstream: `%s`\n' "$h"; fi
      done
      printf '%s\n' "$then_h" | while IFS= read -r h; do
        [ -n "$h" ] || continue
        if ! printf '%s\n' "$now_h" | grep -qxF "$h"; then printf -- '- REMOVED upstream: `%s`\n' "$h"; fi
      done
      printf '\n'
    else
      printf '## Upstream template heading delta\n\n'
      printf -- '- (pin absent — cannot show template-then→template-now delta; presence check below still holds)\n\n'
    fi
    printf '## Presence check — sections in the NEW template vs your file\n\n'
    local h missing_any=0
    printf '%s\n' "$now_h" | while IFS= read -r h; do
      [ -n "$h" ] || continue
      if printf '%s\n' "$user_h" | grep -qxF "$h"; then printf -- '- [present] `%s`\n' "$h"; else printf -- '- [MISSING] `%s` — skeleton staged in incoming/\n' "$h"; fi
    done
    printf '\n'
  } > "$run/$struct"

  # Stage skeleton blocks for MISSING sections into incoming/ (INSERT-BY-HAND).
  local h
  printf '%s\n' "$now_h" | while IFS= read -r h; do
    [ -n "$h" ] || continue
    if ! printf '%s\n' "$user_h" | grep -qxF "$h"; then
      local hsafe block
      hsafe="$(printf '%s' "$h" | tr -c 'A-Za-z0-9._-' '_')"
      block="$(_soif_plan_section_block "$now_tmpl" "$h")"
      {
        printf '<!-- INSERT-BY-HAND: %s — section "%s" from the current framework template.\n' "$artifact" "$h"
        printf '     A2 is agent-authored; copy/adapt this by hand into %s. Not applied by any script. -->\n\n' "$artifact"
        printf '%s\n' "$block"
      } > "$run/incoming/${safe}.section.${hsafe}.md"
    fi
  done

  printf '%s' "$struct"
}

# _soif_plan_headings <file> — normalized heading lines (## / ### / #### plus any
# line beginning "Appendix"). Empty if the file is absent.
_soif_plan_headings() {
  [ -f "$1" ] || return 0
  grep -nE '^#{2,4} ' "$1" 2>/dev/null | sed 's/^[0-9]*://; s/[[:space:]]*$//'
}

# _soif_plan_section_block <file> <heading> — the block from <heading> up to (not
# including) the next heading of the same-or-higher level. Bash-3.2 / BSD-awk safe.
_soif_plan_section_block() {
  local file="$1" head="$2"
  awk -v h="$head" '
    function level(s,   n){ n=0; while(substr(s,n+1,1)=="#") n++; return n }
    BEGIN{ inb=0; hl=0 }
    {
      if (inb==0) {
        if ($0==h) { inb=1; hl=level($0); print; next }
      } else {
        if ($0 ~ /^#{2,6} / && level($0) <= hl) { exit }
        print
      }
    }' "$file" 2>/dev/null
}

# ── UPDATE-PLAN.md emission ──────────────────────────────────────────────────
# THE SELECTION GRAMMAR lives in ONE function so S4's parser has a single anchor.
# # BL-109-PLAN-GRAMMAR — a lint-style test pins the exact line shape:
#   - [ ] <item-id> — <path> (<class>/<verb>)
# Everything defaults UNCHECKED: consent is the operator ticking a box; the plan is
# the offer, never the act.
_soif_plan_grammar_line() {
  local id="$1" path="$2" class="$3" verb="$4"
  printf -- '- [ ] %s — %s (%s/%s)\n' "$id" "$path" "$class" "$verb"   # BL-109-PLAN-GRAMMAR
}

# ── The dispatch (load-bearing) ──────────────────────────────────────────────
# soif_plan_run <project_root> <framework_root> <init_file> <cdf_home> [now_override]
#   Builds the whole run folder. Returns 0 on success (folder built), non-zero on a
#   hard precondition failure (already-exists collision, no manifest). Prints the
#   run-folder path on the final line. Marker # BL-109-PLAN-DISPATCH.
soif_plan_run() {
  local proj="$1" fw="$2" init="$3" cdf="$4" now="${5:-}"
  local mani="$proj/.claude/manifest.json"

  command -v jq >/dev/null 2>&1 || { echo "plan: jq is required" >&2; return 1; }
  [ -f "$mani" ] || { echo "plan: no .claude/manifest.json — not a scaffolded project" >&2; return 1; }

  [ -n "$now" ] || now="$(date +%s)"
  local date_stamp hhmmss fw_head fw_short pin pin_present
  date_stamp="$(date -u -d "@$now" +%Y-%m-%d 2>/dev/null || date -u -r "$now" +%Y-%m-%d 2>/dev/null || date -u +%Y-%m-%d)"
  hhmmss="$(date -u -d "@$now" +%H%M%S 2>/dev/null || date -u -r "$now" +%H%M%S 2>/dev/null || date -u +%H%M%S)"

  fw_head="$(git -C "$fw" rev-parse HEAD 2>/dev/null || echo '')"
  fw_short="$(git -C "$fw" rev-parse --short HEAD 2>/dev/null || echo 'nogit')"
  pin="$(jq -r '.soloFrameworkCommit // empty' "$mani" 2>/dev/null)"
  if [ -n "$pin" ]; then pin_present=true; else pin_present=false; fi

  # Run-id: <YYYY-MM-DD>_<framework-shortsha>_<hhmmss>-<pid> (review-r1 M2). The
  # run folder is created with EXCLUSIVE mkdir — an existing dir is a LOUD abort
  # with no partial folder (# BL-109-PLAN-MKDIR).
  local run_id="${date_stamp}_${fw_short}_${hhmmss}-$$"
  local updates_dir="$proj/docs/updates"
  local RUN_DIR="$updates_dir/$run_id"
  mkdir -p "$updates_dir" 2>/dev/null || true
  if ! mkdir "$RUN_DIR" 2>/dev/null; then          # BL-109-PLAN-MKDIR (exclusive)
    echo "plan: run folder already exists — aborting to avoid clobbering a concurrent run: $RUN_DIR" >&2
    return 1
  fi
  mkdir -p "$RUN_DIR/incoming" "$RUN_DIR/diffs" "$RUN_DIR/review" "$RUN_DIR/archive" \
           "$RUN_DIR/merged" "$RUN_DIR/patches" 2>/dev/null

  # Per-run .gitignore: incoming/ + archive/ are bulky reversible state (design
  # §2-L2 commit scope). Written at run-folder level so EXISTING projects (post-sync)
  # are served without touching the birth-time project .gitignore.
  {
    printf '# BL-109 Currency System plan run — commit scope (design v1.1 §2-L2).\n'
    printf '# UPDATE-PLAN.md + manifest.json + diffs/ + review/ + merged/ + patches/ are committed.\n'
    printf '# incoming/ + archive/ are bulky, reversible, and pruned — never committed.\n'
    printf 'incoming/\n'
    printf 'archive/\n'
  } > "$RUN_DIR/.gitignore"

  # review/ placeholder stub (S4 fills advisory analyses here).
  {
    printf '# review/ — advisory analyses (filled by --apply, S4)\n\n'
    printf 'S4 stages a mid-tier subagent ADVISORY analysis per A1/A2 item here\n'
    printf '(pros / cons / repercussions of skipping). A2 structural diffs also land\n'
    printf 'here at plan time. Advisory output NEVER overrides a mechanical guard\n'
    printf 'and is treated as data, not instructions (review-r1 M8).\n'
  } > "$RUN_DIR/review/README.md"

  # ── Derive items + notices ──────────────────────────────────────────────
  local notices_file items_file
  notices_file="$(mktemp)"; : > "$notices_file"
  items_file="$(mktemp)"
  _soif_plan_derive_items "$proj" "$mani" "$fw" "$init" "$cdf" "$pin_present" "$notices_file" > "$items_file"

  # ── Per-item processing: manifest journal + diffs + candidates + structural ──
  local manitems_file; manitems_file="$(mktemp)"; : > "$manitems_file"
  local plan_rows_file; plan_rows_file="$(mktemp)"; : > "$plan_rows_file"     # for UPDATE-PLAN checkboxes + facts
  local id class verb tier path consent rof
  while IFS="$(printf '\t')" read -r id class verb tier path consent rof; do
    [ -n "$id" ] || continue
    local fw_rel base_sha framework_sha diffstat added removed dfile cand patch struct extra
    fw_rel="$(_soif_plan_fw_relpath "$fw" "$init" "$path")"
    dfile=""; cand=""; patch=""; struct=""; extra=""

    # base-sha = the LIVE file's sha at plan time (via _soif_plan_base_sha,
    # # BL-109-PLAN-BASESHA). framework_sha = the upstream file's sha (empty for
    # retire — the upstream is gone — and for hooks, which diff managed regions).
    base_sha="$(_soif_plan_base_sha "$proj" "$path" "$verb")"
    if [ "$class" = "hook" ]; then
      framework_sha=""
    else
      case "$verb" in
        add)    framework_sha="$(_soif_plan_sha "$fw/$fw_rel")" ;;
        retire) framework_sha="" ;;
        *)      framework_sha="$(_soif_plan_sha "$fw/$fw_rel")" ;;
      esac
    fi

    # diffstat (project-current vs framework-current), verb-aware.
    case "$verb" in
      add)    diffstat="$(_soif_plan_diffstat /dev/null "$fw/$fw_rel")" ;;
      retire) diffstat="$(_soif_plan_diffstat "$proj/$path" /dev/null)" ;;
      *)
        if [ "$class" = "A1" ] || [ "$class" = "A2" ] || [ "$class" = "hook" ]; then
          diffstat="- -"
        else
          diffstat="$(_soif_plan_diffstat "$proj/$path" "$fw/$fw_rel")"
        fi ;;
    esac
    added="${diffstat%% *}"; removed="${diffstat##* }"

    # Class dispatch — A2 NEVER reaches the A1 candidate path (# BL-109-PLAN-A2FENCE).
    case "$class" in
      A1)
        extra="$(_soif_plan_build_a1_candidate "$RUN_DIR" "$proj" "$fw" "$pin" "$pin_present" "$id" "$path")"
        cand="$(printf '%s' "$extra" | cut -f1)"; patch="$(printf '%s' "$extra" | cut -f2)" ;;
      A2)
        struct="$(_soif_plan_build_a2_structural "$RUN_DIR" "$proj" "$fw" "$pin" "$pin_present" "$id" "$path")" ;;   # BL-109-PLAN-A2FENCE
      hook)
        : ;;                                      # hook full diff is embedded in UPDATE-PLAN
      *)
        dfile="$(_soif_plan_build_diff "$RUN_DIR" "$proj" "$fw" "$init" "$pin" "$pin_present" "$id" "$verb" "$path")" ;;
    esac

    # manifest item (journal-of-record). Normalize diffstat to valid JSON numbers
    # (A1/A2/hook carry "-" which is "see diff" in UPDATE-PLAN, 0 in the journal).
    local added_json removed_json
    case "$added" in   ''|*[!0-9]*) added_json=0 ;;   *) added_json="$added" ;;   esac
    case "$removed" in ''|*[!0-9]*) removed_json=0 ;; *) removed_json="$removed" ;; esac
    jq -nc \
      --arg id "$id" --arg path "$path" --arg class "$class" --arg verb "$verb" \
      --arg tier "$tier" --arg consent "$consent" --arg base "$base_sha" \
      --arg fwsha "$framework_sha" --arg prov "$fw_short" --arg rof "$rof" \
      --arg dfile "$dfile" --arg cand "$cand" --arg patch "$patch" --arg struct "$struct" \
      --argjson added "$added_json" --argjson removed "$removed_json" '
      { id:$id, path:$path, class:$class, verb:$verb, tier:$tier, consent:$consent,
        baseSha:(if $base=="" then null else $base end),
        frameworkSha:(if $fwsha=="" then null else $fwsha end),
        provenance:$prov,
        renameOf:(if $rof=="" then null else $rof end),
        diffstat:{added:$added, removed:$removed},
        diff:(if $dfile=="" then null else $dfile end),
        candidate:(if $cand=="" then null else $cand end),
        patch:(if $patch=="" then null else $patch end),
        structural:(if $struct=="" then null else $struct end),
        selected:false }' >> "$manitems_file"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$id" "$class" "$verb" "$tier" "$path" "$consent" "$added" "$removed" \
      "$([ -n "$base_sha" ] && _soif_plan_short "$base_sha" || printf '-')" >> "$plan_rows_file"
  done < "$items_file"

  # ── manifest.json (journal-of-record) ───────────────────────────────────
  local items_json total
  items_json="$(jq -sc '.' "$manitems_file" 2>/dev/null)"; [ -n "$items_json" ] || items_json='[]'
  total="$(printf '%s' "$items_json" | jq 'length')"
  jq -n \
    --arg runId "$run_id" --arg gen "$(_soif_plan_iso "$now")" \
    --arg fwpath "$fw" --arg head "$fw_head" --arg headShort "$fw_short" \
    --arg pin "$pin" --argjson pinPresent "$pin_present" \
    --argjson items "$items_json" '
    { schema:"soif-plan/1", runId:$runId, generatedAt:$gen,
      framework:{ path:$fwpath, head:$head, headShort:$headShort,
                  pin:(if $pin=="" then null else $pin end), pinPresent:$pinPresent },
      counts:{ total:($items|length),
               byVerb:($items|group_by(.verb)|map({key:.[0].verb,value:length})|from_entries),
               byClass:($items|group_by(.class)|map({key:.[0].class,value:length})|from_entries) },
      items:$items }' > "$RUN_DIR/manifest.json"

  # ── UPDATE-PLAN.md (# BL-109-PLAN-FENCE — the run-confined selection surface) ──
  _soif_plan_emit_update_plan "$RUN_DIR" "$run_id" "$now" "$fw" "$fw_head" "$fw_short" \
      "$pin" "$pin_present" "$total" "$plan_rows_file" "$notices_file" "$proj" \
      > "$RUN_DIR/UPDATE-PLAN.md"                    # BL-109-PLAN-FENCE

  rm -f "$notices_file" "$items_file" "$manitems_file" "$plan_rows_file" 2>/dev/null || true
  printf '%s\n' "$RUN_DIR"
  return 0
}

# _soif_plan_emit_update_plan ... > UPDATE-PLAN.md — the human review doc + the
# checkbox selection surface. Mechanical facts table + one grammar line per item;
# hook/gate items carry the FULL unified diff inline (I11).
_soif_plan_emit_update_plan() {
  local run="$1" run_id="$2" now="$3" fw="$4" fw_head="$5" fw_short="$6" \
        pin="$7" pin_present="$8" total="$9" rows="${10}" notices="${11}" proj="${12}"
  local pin_disp
  if [ "$pin_present" = true ]; then pin_disp="$(_soif_plan_short "$pin") → $(_soif_plan_short "$fw_head")"; else pin_disp="(absent) → $(_soif_plan_short "$fw_head")"; fi

  printf '# Framework Update Plan — %s\n\n' "$run_id"
  printf '**Generated:** %s  \n' "$(_soif_plan_iso "$now")"
  printf '**Framework pin → HEAD:** `%s`  \n' "$pin_disp"
  printf '**Items:** %s\n\n' "$total"
  printf 'This is an OFFER, not an action. Nothing here has been applied. Every box is\n'
  printf 'UNCHECKED by default — tick the ones you want, then run `--apply` (S4). The\n'
  printf 'checkbox list is the SINGLE selection surface (review-r1 M4). All facts in the\n'
  printf 'table are script-computed (review-r1 M8).\n\n'

  # Notices (pin-absent, local edits, pin-behind, CDF).
  if [ "$pin_present" != true ]; then
    printf '> ⚠ **Framework pin absent (BL-110).** This project has no `soloFrameworkCommit`.\n'
    printf '> Framework-drift, add/retire/rename staging, and A1 candidate generation are\n'
    printf '> UNAVAILABLE until the pin is stamped (run `--sync-framework` once, which stamps\n'
    printf '> it). Local-edit / hook / render-base items below are still derived.\n\n'
  fi
  if [ -s "$notices" ]; then
    local kind nmsg printed=0
    while IFS="$(printf '\t')" read -r kind nmsg; do
      [ -n "$kind" ] || continue
      if [ "$printed" = 0 ]; then printf '## Notices\n\n'; printed=1; fi
      printf -- '- (%s) %s\n' "$kind" "$nmsg"
    done < "$notices"
    [ "$printed" = 1 ] && printf '\n'
  fi

  if [ "$total" = "0" ]; then
    printf '## No updates available\n\nEverything tracked is current. Nothing to select.\n'
    return 0
  fi

  # Mechanical facts table.
  printf '## Mechanical facts\n\n'
  printf '| item-id | class | verb | +/- | base-sha | tier |\n'
  printf '|---|---|---|---|---|---|\n'
  local id class verb tier path consent added removed bshort
  while IFS="$(printf '\t')" read -r id class verb tier path consent added removed bshort; do
    [ -n "$id" ] || continue
    local ds
    if [ "$added" = "-" ] || [ "$class" = "A1" ] || [ "$class" = "A2" ] || [ "$class" = "hook" ]; then ds="see diff"; else ds="+$added/-$removed"; fi
    printf '| `%s` | %s | %s | %s | `%s` | %s |\n' "$id" "$class" "$verb" "$ds" "$bshort" "$tier"
  done < "$rows"
  printf '\n'

  # Selection surface — one grammar line per item, ALL UNCHECKED.
  printf '## Selection — tick to include (default: none)\n\n'
  while IFS="$(printf '\t')" read -r id class verb tier path consent added removed bshort; do
    [ -n "$id" ] || continue
    _soif_plan_grammar_line "$id" "$path" "$class" "$verb"
    if [ "$consent" = "item" ]; then printf '      ⚠ item-consent required (%s)\n' "$tier"; fi
  done < "$rows"
  printf '\n'

  # Item-consent details: hooks + gate scripts embed the FULL unified diff (I11).
  local any_hook=0
  while IFS="$(printf '\t')" read -r id class verb tier path consent added removed bshort; do
    [ -n "$id" ] || continue
    if [ "$class" = "hook" ]; then
      if [ "$any_hook" = 0 ]; then printf '## Item-consent: hooks / gate scripts (full diff, I11)\n\n'; any_hook=1; fi
      printf '### `%s` — %s (%s)\n\n' "$id" "$path" "$verb"
      printf 'Hooks and gate scripts are NEVER batch-consented (invariant I11). Review the\n'
      printf 'full managed-block diff below and provenance before ticking this item.\n\n'
      printf '**Provenance:** framework `%s`\n\n' "$(_soif_plan_short "$fw_head")"
      printf '```diff\n'
      _soif_plan_hook_full_diff "$proj" "$fw" "$path" "$id"
      printf '```\n\n'
    fi
  done < "$rows"

  # A1 no-agent application protocol.
  local any_a1=0
  while IFS="$(printf '\t')" read -r id class verb tier path consent added removed bshort; do
    [ -n "$id" ] || continue
    if [ "$class" = "A1" ]; then any_a1=1; fi
  done < "$rows"
  if [ "$any_a1" = 1 ]; then
    printf '## Applying an A1 candidate (CLAUDE.md / PROJECT_INTAKE.md) — by hand\n\n'
    printf 'A1 docs are script-RENDERED. This plan stages a three-way candidate built from\n'
    printf 'the old template (at the pin) and the new template, both re-rendered with your\n'
    printf 'recovered project vars — so NO template placeholder can reach the merge\n'
    printf '(review-r1 B3b). Conflict markers, if any, STAY in the candidate for you to\n'
    printf 'resolve. The updater NEVER writes these files (invariant I2). To apply one\n'
    printf 'after review, from the project root:\n\n'
    printf '```sh\n'
    printf '# option A — apply the patch:\n'
    printf 'git apply "%s/patches/<artifact>.patch"\n' "docs/updates/$run_id"
    printf '# option B — copy the reviewed candidate over your file:\n'
    printf 'cp "%s/merged/<artifact>.candidate" <artifact>\n' "docs/updates/$run_id"
    printf '```\n\n'
    printf 'Then resolve any `<<<<<<<` conflict markers by hand and re-run your tests.\n\n'
  fi

  printf -- '---\n_Selection is one-way: `--apply` (S4) parses the ticked boxes into `manifest.json` as journal; it never reads the journal back as input._\n'
}

# _soif_plan_hook_full_diff <proj> <fw> <hookpath> <id> — the full unified diff of a
# hook's installed managed block vs the framework's current template body. Best-
# effort + mechanical; never a network op.
_soif_plan_hook_full_diff() {
  local proj="$1" fw="$2" hookpath="$3" id="$4"
  local name="${hookpath##*/}" installed="$proj/$hookpath"
  local fw_hooktpl="$fw/scripts/lib/hook-templates.sh" open close bodyfn
  case "$name" in
    pre-commit) open="${SOIF_PRECOMMIT_OPEN:-}"; close="${SOIF_PRECOMMIT_CLOSE:-}"; bodyfn=soif_precommit_region_body ;;
    commit-msg) open="${SOIF_TDD_OPEN:-}";       close="${SOIF_TDD_CLOSE:-}";       bodyfn=soif_tdd_region_body ;;
    *) open=""; close=""; bodyfn="" ;;
  esac
  local cur_block="" cur_tpl=""
  if [ -f "$installed" ] && [ -n "$open" ]; then
    cur_block="$(awk -v o="$open" -v c="$close" 'index($0,o){f=1} f{print} index($0,c){f=0}' "$installed" 2>/dev/null)"
  fi
  if [ -n "$bodyfn" ] && [ -f "$fw_hooktpl" ]; then
    cur_tpl="$( . "$fw_hooktpl" >/dev/null 2>&1; "$bodyfn" 2>/dev/null )"
  fi
  local a b; a="$(mktemp)"; b="$(mktemp)"
  printf '%s\n' "$cur_block" > "$a"
  printf '%s\n' "$cur_tpl"   > "$b"
  diff -u -L "installed/$name" -L "framework/$name" "$a" "$b" 2>/dev/null || true
  rm -f "$a" "$b" 2>/dev/null || true
}

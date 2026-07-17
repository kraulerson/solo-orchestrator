#!/usr/bin/env bash
# scripts/lib/freshness-detect.sh
#
# BL-109 SLICE-S2 (Layer 1 — Detection). The read-only session-start freshness
# detector for the Currency System (design v1.1 §2-L1; invariant I7). Consumed
# by scripts/session-freshness-check.sh (the SessionStart hook wrapper). Pure
# detection + an atomic snooze cache — NO staging, NO plan, NO apply.
#
# CONTRACT (design v1.1 §2-L1 + I7 + review-r1 M5/M6/M9):
#   • SILENT when current — zero bytes on stdout/stderr (Appendix P rung 1).
#   • ZERO network — ever. Reads the LOCAL framework/CDF clones' files + refs
#     only; never git fetch / ls-remote / curl.
#   • Writes NOTHING in the project tree except `.claude/cache/freshness.json`
#     (temp-write in the SAME dir + atomic rename; torn/invalid = cold start,
#     never fatal; embedded FUTURE timestamps are clamped to expired).
#   • Fail-open: the caller wraps the dispatch so any internal fault yields
#     exit 0 (I7 — a broken checker must not brick a session). This lib returns
#     0 on the normal path and only nonzero on a genuine internal fault.
#   • Tiered output: ENFORCEMENT drift first ("recommended now"), then
#     INFORMATIONAL. Snooze: informational holds until the upstream delta
#     changes; ENFORCEMENT auto-expires after 7 days AND is recorded through
#     scripts/lib/bypass-audit.sh (review-r1 M5). Standing line
#     "N enforcement items snoozed" prints while any enforcement snooze is held,
#     even if otherwise current.
#
# CHECKS (all local; §2-L1 a–f):
#   (a) LOCAL-EDIT     — project's framework-owned files (class M/T) vs files{}
#                        → informational ('local edits … sync would archive-and-replace').
#   (b) FRAMEWORK-DRIFT— via soloFrameworkPath: pin vs framework HEAD
#                        (informational 'N commits behind') + per-file shas of
#                        the framework's CURRENT shipped set vs files{}
#                        (gate scripts/hooks → ENFORCEMENT; other → informational).
#                        Skips SILENTLY when the path is missing / not a git
#                        checkout OR soloFrameworkCommit is absent (BL-110 interim).
#   (c) ORPHANS        — files{} entries whose upstream source no longer exists
#                        → ENFORCEMENT (design B4).
#   (d) HOOK CURRENCY  — installed hook managed-blocks vs the framework's current
#                        templates. hooks{} expectation enum honored (review-r1 M9):
#                        absent-intentional → silent; absent-unavailable →
#                        ENFORCEMENT ('TDD gate unavailable for this language —
#                        BL-107'); present-but-missing / drift → ENFORCEMENT.
#   (e) RENDER-BASE    — A1/A2 template shas vs the framework's current templates
#                        → informational ('your CLAUDE.md was rendered from an
#                        older template').
#   (f) CDF STALENESS  — read-only via the existing cdf-refresh surfaces
#                        (frameworkCommit pin vs the local CDF clone HEAD) →
#                        informational. Skips silently if the clone is absent.
#   TOOLS — NOT covered here. The existing data-driven check
#           (scripts/check-versions.sh + its session-version-check.sh wiring)
#           owns tools; S2 does not duplicate it (see the machine-block schema:
#           "toolsCovered": false).
#
# bash-3.2 safe: no associative arrays, no `[[ -v ]]`, no `((x++))` under set -e,
# no `nullglob`. This lib assumes the CALLER does NOT run under `set -e`
# (fail-open). Depends on: jq, git (local reads), shasum, and the sibling libs
# currency-manifest.sh + hook-templates.sh (sourced by the caller/script).

# ── Wiring: source sibling libs if a caller has not already ──────────────────
_soif_fd_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v soif_currency_sha256 >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  [ -f "$_soif_fd_dir/currency-manifest.sh" ] && . "$_soif_fd_dir/currency-manifest.sh"
fi
if ! command -v soif_tdd_region_body >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  [ -f "$_soif_fd_dir/hook-templates.sh" ] && . "$_soif_fd_dir/hook-templates.sh"
fi
unset _soif_fd_dir

# Enforcement-tier auto-expiry window for snoozes (review-r1 M5): 7 days.
SOIF_FRESH_ENFORCE_SNOOZE_SECS=604800   # 7 * 24 * 60 * 60

# ── Primitives ───────────────────────────────────────────────────────────────
# soif_freshness_now — current epoch seconds. SOIF_FRESHNESS_NOW overrides it
# (deterministic snooze-boundary tests). Never touches the network.
soif_freshness_now() {
  if [ -n "${SOIF_FRESHNESS_NOW:-}" ]; then
    printf '%s' "$SOIF_FRESHNESS_NOW"
  else
    date +%s
  fi
}

# _soif_fresh_sha <file> — hex sha256, empty on missing. Reuses the currency lib
# primitive when available, else a local shasum fallback.
_soif_fresh_sha() {
  if command -v soif_currency_sha256 >/dev/null 2>&1; then
    soif_currency_sha256 "$1" 2>/dev/null
  else
    [ -f "$1" ] || return 1
    shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  fi
}

# _soif_fresh_is_enforcement_path <rel> — 0 if this tracked path is a gate
# script / hook (its drift is ENFORCEMENT tier), else 1. Mirrors CLAUDE.md's
# ENFORCEMENT source-of-truth list + everything under scripts/hooks/.
_soif_fresh_is_enforcement_path() {
  case "$1" in
    scripts/pre-commit-gate.sh|scripts/check-phase-gate.sh|scripts/check-gate.sh|\
    scripts/process-checklist.sh|scripts/run-phase3-validation.sh|\
    scripts/lib/tdd-classify.sh|scripts/lib/enforcement-level.sh|\
    scripts/lib/gate-principles.sh|scripts/lib/hook-templates.sh|\
    scripts/hooks/*)
      return 0 ;;
    *)
      return 1 ;;
  esac
}

# _soif_fresh_fw_source <fw_dir> <init_file> <rel> — echo the framework SOURCE
# abspath a downstream tracked rel-path was shipped FROM, or empty if it is not
# a mechanically-mappable class (A1 renders are handled by the render-base
# check, never here). Relocations are mechanical (init.sh is the source of
# truth): scripts keep their path; skills come from templates/generated/skills;
# reference docs come from docs/<base> (resolved off init.sh's own cp line).
_soif_fresh_fw_source() {
  local fw="$1" init="$2" rel="$3" name base src
  case "$rel" in
    scripts/*)
      printf '%s/%s' "$fw" "$rel" ;;
    templates/generated/*)
      # BL-109 S3: the bulk Class-T project templates (soif_parse_shipped_templates)
      # ship byte-for-byte from the same relative path in the framework tree.
      printf '%s/%s' "$fw" "$rel" ;;
    .claude/skills/*)
      name="${rel#.claude/skills/}"
      printf '%s/templates/generated/skills/%s' "$fw" "$name" ;;
    docs/reference/*)
      base="${rel#docs/reference/}"
      src="$(grep -E 'cp[[:space:]]+"\$SCRIPT_DIR/docs/[^"]*'"$base"'"[[:space:]]+docs/reference/' "$init" 2>/dev/null \
        | head -1 \
        | sed -n 's#.*cp[[:space:]]*"\$SCRIPT_DIR/\(docs/[^"]*\)".*#\1#p')"
      if [ -n "$src" ]; then
        printf '%s/%s' "$fw" "$src"
      else
        printf '%s/docs/%s' "$fw" "$base"
      fi ;;
    *)
      printf '' ;;
  esac
}

# _soif_fresh_is_git_checkout <dir> — 0 if <dir> is a git work-tree (LOCAL read
# only; never network).
_soif_fresh_is_git_checkout() {
  [ -n "$1" ] || return 1
  [ -d "$1" ] || return 1
  git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# ── Item emitter ─────────────────────────────────────────────────────────────
# Every drift item is one TSV line, all fields present (empty allowed):
#   id \t check \t tier \t path \t verb \t sig \t message
# `sig` is the per-item delta signature used only for snooze delta-change
# detection; it is cache-internal and is NOT emitted in the machine block.
_soif_fresh_emit() {
  # <id> <check> <tier> <path> <verb> <sig> <message...>
  local id="$1" check="$2" tier="$3" path="$4" verb="$5" sig="$6"
  shift 6
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$check" "$tier" "$path" "$verb" "$sig" "$*"
}

# ── (a) LOCAL-EDIT ───────────────────────────────────────────────────────────
_soif_fresh_check_local_edits() {
  local proj="$1" mani="$2" line rel msha cls disk_sha
  jq -r '.currency.files // {} | to_entries[]
         | select(.value.class=="M" or .value.class=="T")
         | "\(.key)\t\(.value.sha256)\t\(.value.class)"' "$mani" 2>/dev/null \
  | while IFS="$(printf '\t')" read -r rel msha cls; do
      [ -n "$rel" ] || continue
      [ -f "$proj/$rel" ] || continue          # absent locally is an orphan/hook concern, not a local edit
      disk_sha="$(_soif_fresh_sha "$proj/$rel")"
      [ -n "$disk_sha" ] || continue
      if [ "$disk_sha" != "$msha" ]; then
        _soif_fresh_emit "local-edit:$rel" local-edit informational "$rel" update "$disk_sha" \
          "local edit to framework-managed file $rel (a sync would archive-and-replace it)"
      fi
    done
}

# ── (b) FRAMEWORK-DRIFT + (c) ORPHANS ────────────────────────────────────────
_soif_fresh_check_framework() {
  local proj="$1" mani="$2" fw="$3" init="$4"
  local pin head sig rel msha cls src src_sha tier verb

  pin="$(jq -r '.soloFrameworkCommit // empty' "$mani" 2>/dev/null)"

  # Skip contract (design §2-L0 + BL-110 interim): no path, not a git checkout,
  # or pin absent → skip SILENTLY (never a crash, never false drift).
  _soif_fresh_is_git_checkout "$fw" || return 0
  [ -n "$pin" ] || return 0

  head="$(git -C "$fw" rev-parse HEAD 2>/dev/null)"
  sig="${pin}..${head}"

  # pin vs HEAD — informational "N commits behind" (only when the pin is a known
  # ancestor of HEAD; a shallow/absent pin object → no history line, per M1's
  # never-fetch rule; per-file drift below still runs).
  if [ -n "$head" ] && [ "$pin" != "$head" ]; then
    if git -C "$fw" merge-base --is-ancestor "$pin" HEAD >/dev/null 2>&1; then
      local n
      n="$(git -C "$fw" rev-list --count "$pin"..HEAD 2>/dev/null)"
      if [ -n "$n" ] && [ "$n" != "0" ]; then
        _soif_fresh_emit "pin-behind" framework informational "-" update "$sig" \
          "framework clone is $n commit(s) ahead of your pin (${pin} → ${head})"
      fi
    fi
  fi

  # per-file drift + orphans over class M/T (A1 handled by render-base).
  jq -r '.currency.files // {} | to_entries[]
         | select(.value.class=="M" or .value.class=="T")
         | "\(.key)\t\(.value.sha256)\t\(.value.class)"' "$mani" 2>/dev/null \
  | while IFS="$(printf '\t')" read -r rel msha cls; do
      [ -n "$rel" ] || continue
      src="$(_soif_fresh_fw_source "$fw" "$init" "$rel")"
      [ -n "$src" ] || continue                # unmappable class — leave to other checks

      # (b0) MISSING LOCALLY (# BL-109-MISSING) — the manifest tracks it, but it is GONE
      # from the project tree (an operator deleted it). This arm exists because the drift
      # comparison below is MANIFEST-sha vs UPSTREAM-sha and never looked at the project
      # file at all: a deleted-but-still-tracked gate script therefore surfaced as ordinary
      # framework-drift with verb `update`, whose diff has no base — an EMPTY payload — and
      # S3's fail-closed I11 payload guard then aborted the ENTIRE plan, naming the payload
      # and the verb rather than the true cause, and taking every unrelated item down with
      # it. The condition is now detected explicitly and named for what it is.
      if [ ! -f "$proj/$rel" ]; then
        if [ -f "$src" ]; then
          # Still shipped upstream → OFFER IT BACK. A `add` verb, whose diff is a real
          # /dev/null → upstream addition, so the I11 payload contract holds by
          # construction. A deleted gate script is exactly the drift the operator most
          # needs offered back, so refusing here would be the wrong kind of safe.
          if _soif_fresh_is_enforcement_path "$rel"; then tier=enforcement; else tier=informational; fi
          _soif_fresh_emit "missing:$rel" missing "$tier" "$rel" add "$(_soif_fresh_sha "$src")" \
            "tracked file is missing from the project: $rel is tracked but not on disk (a sync would restore it from the framework)"
        else
          # Gone from BOTH sides: nothing to restore, and nothing on disk to retire. The
          # manifest entry is simply stale. Emitting an `orphan`/retire here would promise
          # to delete a file that is already gone — and its retire diff would be empty,
          # which is the same hollow abort one verb over. The plan renders this as a
          # NOTICE, never a checkbox (verb `untrack` = no filesystem action).
          _soif_fresh_emit "missing:$rel" missing informational "$rel" untrack "gone@$head" \
            "tracked file is missing from the project AND no longer exists upstream: $rel — nothing to apply; the manifest entry is stale (a sync would drop it)"
        fi
        continue
      fi

      if [ ! -f "$src" ]; then
        # (c) ORPHAN — the manifest ships it but upstream deleted the source.
        _soif_fresh_emit "orphan:$rel" orphan enforcement "$rel" retire "gone@$head" \
          "orphaned: $rel is tracked but no longer exists upstream (a sync would retire it)"
        continue
      fi
      src_sha="$(_soif_fresh_sha "$src")"
      [ -n "$src_sha" ] || continue
      if [ "$src_sha" != "$msha" ]; then
        if _soif_fresh_is_enforcement_path "$rel"; then
          tier=enforcement
        else
          tier=informational
        fi
        _soif_fresh_emit "fw-drift:$rel" framework-drift "$tier" "$rel" update "$src_sha" \
          "framework updated $rel since you installed it (a sync would refresh it)"
      fi
    done
}

# ── (d) HOOK CURRENCY ────────────────────────────────────────────────────────
# Installed hook managed-blocks vs the framework's current templates. The
# expectation enum comes from the MANIFEST (no framework needed for the
# missing / absent-unavailable arms); the DRIFT arm needs the framework's
# current template and is skipped silently when the framework is unavailable.
_soif_fresh_check_hooks() {
  local proj="$1" mani="$2" fw="$3"
  local hooks want hookfile block current
  hooks="$(jq -r '.currency.hooks // {} | to_entries[] | "\(.key)\t\(.value)"' "$mani" 2>/dev/null)"
  [ -n "$hooks" ] || return 0

  # Prefer the framework's CURRENT hook templates for the drift comparison
  # (a downstream copy may itself be stale). Source them from the framework
  # clone if present; else fall back to whatever is already sourced.
  local fw_hooktpl=""
  if [ -n "$fw" ] && [ -f "$fw/scripts/lib/hook-templates.sh" ]; then
    fw_hooktpl="$fw/scripts/lib/hook-templates.sh"
  fi

  printf '%s\n' "$hooks" | while IFS="$(printf '\t')" read -r want_name want_state; do
    [ -n "$want_name" ] || continue
    case "$want_state" in
      absent-intentional)
        # BL-107-UNIVERSAL-INSTALL: since BL-107 nothing WRITES this value —
        # the commit-msg gate installs for every language — so a manifest
        # carrying it can only be a LEGACY pre-BL-107 scaffold (rust) whose
        # TDD gate is still missing. Surfacing it has zero false positives;
        # the old silent arm meant exactly the ticket's headline axis (rust)
        # never heard its gate now exists (verifier finding, 2026-07-17).
        _soif_fresh_emit "hook-legacy-absent:$want_name" hook enforcement "-" add "legacy-absent" \
          "legacy pre-BL-107 manifest: the $want_name TDD gate now installs for every language — run upgrade-project.sh --sync-framework to install it (BL-107)" ;;
      absent-unavailable)
        # review-r1 M9 + BL-107 — never launder a bug into a fact.
        _soif_fresh_emit "hook-unavailable:$want_name" hook enforcement "-" add "unavailable" \
          "TDD gate unavailable for this language ($want_name hook not installed) — BL-107" ;;
      present)
        hookfile="$proj/.git/hooks/$want_name"
        # Which managed-region emitter + markers govern this hook?
        local open close bodyfn
        case "$want_name" in
          pre-commit)  open="$SOIF_PRECOMMIT_OPEN"; close="$SOIF_PRECOMMIT_CLOSE"; bodyfn=soif_precommit_region_body ;;
          commit-msg)  open="$SOIF_TDD_OPEN";       close="$SOIF_TDD_CLOSE";       bodyfn=soif_tdd_region_body ;;
          *)           open=""; close=""; bodyfn="" ;;
        esac
        if [ ! -f "$hookfile" ] || [ -z "$open" ] || ! grep -qF "$open" "$hookfile" 2>/dev/null; then
          _soif_fresh_emit "hook-missing:$want_name" hook enforcement "-" add "missing" \
            "$want_name hook is expected but its managed block is missing (a sync would reinstall it)"
          continue
        fi
        # DRIFT — compare the installed managed region to the current template.
        # Needs the emitter; if we cannot resolve a current template, skip the
        # drift arm silently (missing was already handled above).
        [ -n "$bodyfn" ] || continue
        block="$(awk -v o="$open" -v c="$close" '
          index($0,o){f=1} f{print} index($0,c){f=0}' "$hookfile" 2>/dev/null)"
        current="$(
          if [ -n "$fw_hooktpl" ]; then
            ( . "$fw_hooktpl" >/dev/null 2>&1; "$bodyfn" 2>/dev/null )
          else
            "$bodyfn" 2>/dev/null
          fi
        )"
        [ -n "$current" ] || continue
        if [ "$(printf '%s' "$block" | _soif_fresh_stdin_sha)" != "$(printf '%s' "$current" | _soif_fresh_stdin_sha)" ]; then
          _soif_fresh_emit "hook-drift:$want_name" hook enforcement "-" update \
            "$(printf '%s' "$current" | _soif_fresh_stdin_sha)" \
            "$want_name hook managed block is stale vs the framework template (a sync would refresh it)"
        fi ;;
      *)
        : ;;                                    # unknown enum value — stay silent
    esac
  done
}

# _soif_fresh_stdin_sha — sha256 of stdin, hex only (portable helper for block
# comparison without temp files).
_soif_fresh_stdin_sha() {
  shasum -a 256 2>/dev/null | awk '{print $1}'
}

# ── (e) RENDER-BASE drift ────────────────────────────────────────────────────
_soif_fresh_check_render_base() {
  local mani="$1" fw="$2"
  [ -n "$fw" ] || return 0
  local rows group artifact tpl mtpl_sha ftpl_sha
  # (group, artifact, framework-template-relpath) — the stable A1/A2 mapping.
  rows='A1	CLAUDE.md	templates/generated/claude-md.tmpl
A1	PROJECT_INTAKE.md	templates/project-intake.md
A2	PROJECT_BIBLE.md	templates/generated/project-bible.tmpl
A2	PRODUCT_MANIFESTO.md	templates/generated/product-manifesto.tmpl'
  printf '%s\n' "$rows" | while IFS="$(printf '\t')" read -r group artifact tpl; do
    [ -n "$artifact" ] || continue
    mtpl_sha="$(jq -r --arg g "$group" --arg a "$artifact" \
      '.currency.renderBases[$g][$a].templateSha // empty' "$mani" 2>/dev/null)"
    [ -n "$mtpl_sha" ] || continue
    [ -f "$fw/$tpl" ] || continue
    ftpl_sha="$(_soif_fresh_sha "$fw/$tpl")"
    [ -n "$ftpl_sha" ] || continue
    if [ "$ftpl_sha" != "$mtpl_sha" ]; then
      _soif_fresh_emit "render-base:$artifact" render-base informational "$artifact" update "$ftpl_sha" \
        "your $artifact was rendered from an older template (the framework template changed)"
    fi
  done
}

# ── (f) CDF STALENESS (read-only) ────────────────────────────────────────────
_soif_fresh_check_cdf() {
  local mani="$1" cdf_home="$2"
  local pin head n
  pin="$(jq -r '.frameworkCommit // empty' "$mani" 2>/dev/null)"
  [ -n "$pin" ] || return 0
  _soif_fresh_is_git_checkout "$cdf_home" || return 0     # clone absent → silent
  head="$(git -C "$cdf_home" rev-parse HEAD 2>/dev/null)"
  [ -n "$head" ] || return 0
  [ "$pin" != "$head" ] || return 0
  git -C "$cdf_home" merge-base --is-ancestor "$pin" HEAD >/dev/null 2>&1 || return 0
  n="$(git -C "$cdf_home" rev-list --count "$pin"..HEAD 2>/dev/null)"
  [ -n "$n" ] && [ "$n" != "0" ] || return 0
  _soif_fresh_emit "cdf-behind" cdf informational "-" update "${pin}..${head}" \
    "Development Guardrails (CDF) clone is $n commit(s) ahead of your pin"
}

# ── The dispatch (load-bearing) ──────────────────────────────────────────────
# soif_freshness_detect <proj> <mani> <fw_dir> <init_file> <cdf_home>
#   Runs EVERY check and prints the union of drift items (TSV) to stdout.
#   Prints nothing when everything is current.
soif_freshness_detect() {
  local proj="$1" mani="$2" fw="$3" init="$4" cdf="$5"
  # BL-109-FRESHNESS — neutering this body (checks not run) makes ALL drift
  # detection go dark. The fail-open wrapper and cache/snooze logic are separate
  # so this marker isolates the detection surface for the mutation proof.
  _soif_fresh_check_local_edits   "$proj" "$mani"
  _soif_fresh_check_framework     "$proj" "$mani" "$fw" "$init"
  _soif_fresh_check_hooks         "$proj" "$mani" "$fw"
  _soif_fresh_check_render_base   "$mani" "$fw"
  _soif_fresh_check_cdf           "$mani" "$cdf"
}

# ── Cache (I7) ───────────────────────────────────────────────────────────────
# _soif_fresh_cache_read <cache_file> — echo valid cache JSON, or `{}` for a
# missing/torn/invalid cache (cold start, never fatal).
_soif_fresh_cache_read() {
  local f="$1"
  [ -f "$f" ] || { printf '{}'; return 0; }
  if jq -e 'type=="object"' "$f" >/dev/null 2>&1; then
    cat "$f"
  else
    printf '{}'
  fi
}

# _soif_fresh_cache_write <cache_file> <json> — temp-write in the SAME directory
# + atomic rename. Never fatal (a write failure is swallowed — detection must
# not brick a session).
_soif_fresh_cache_write() {
  local f="$1" json="$2" dir tmp
  dir="$(dirname "$f")"
  mkdir -p "$dir" 2>/dev/null || return 0
  tmp="$(mktemp "$dir/.freshness.XXXXXX" 2>/dev/null)" || return 0
  if printf '%s\n' "$json" | jq . > "$tmp" 2>/dev/null; then
    mv "$tmp" "$f" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
  fi
  return 0
}

# _soif_fresh_snooze_held <cache_json> <id> <tier> <sig> <now> — 0 if a live
# snooze suppresses this item, else 1. Informational snoozes hold while the
# stored deltaSig still matches the item's current sig; ENFORCEMENT snoozes hold
# only while ALSO within the 7-day window (review-r1 M5). A stored snoozedAt in
# the FUTURE is clamped to "expired" (safe direction — re-surface).
_soif_fresh_snooze_held() {
  local cache="$1" id="$2" tier="$3" sig="$4" now="$5"
  local stored_sig stored_at age
  stored_sig="$(printf '%s' "$cache" | jq -r --arg id "$id" '.snoozes[$id].deltaSig // empty' 2>/dev/null)"
  [ -n "$stored_sig" ] || return 1              # not snoozed
  [ "$stored_sig" = "$sig" ] || return 1        # upstream delta moved → void
  if [ "$tier" = "enforcement" ]; then
    stored_at="$(printf '%s' "$cache" | jq -r --arg id "$id" '.snoozes[$id].snoozedAt // empty' 2>/dev/null)"
    case "$stored_at" in ''|*[!0-9]*) return 1 ;; esac
    # FUTURE-timestamp clamp: snoozedAt > now → treat as expired.
    [ "$stored_at" -le "$now" ] || return 1     # BL-109-FRESHNESS-EXPIRY (clamp)
    age=$(( now - stored_at ))
    [ "$age" -lt "$SOIF_FRESH_ENFORCE_SNOOZE_SECS" ] || return 1   # BL-109-FRESHNESS-EXPIRY (7-day)
  fi
  return 0
}

# ── Rendering ────────────────────────────────────────────────────────────────
# _soif_fresh_machine_json <items_tsv> <now> <enf_snoozed> — the fenced machine
# block payload (stable-key JSON; schema "soif-freshness/1").
_soif_fresh_machine_json() {
  local items="$1" now="$2" enf_snoozed="$3" gen items_json current
  gen="$(_soif_fresh_iso "$now")"
  items_json="$(printf '%s\n' "$items" | jq -Rn '
    [ inputs | select(length>0) | split("\t")
      | { id:.[0], check:.[1], tier:.[2],
          path:(if (.[3]=="" or .[3]=="-") then null else .[3] end),
          verb:(if (.[4]=="" or .[4]=="-") then null else .[4] end),
          message:.[6] } ]')"
  if [ -z "$(printf '%s' "$items" | tr -d '[:space:]')" ]; then
    items_json='[]'
  fi
  if [ "$items_json" = "[]" ]; then current=true; else current=false; fi
  jq -n \
    --arg gen "$gen" \
    --argjson items "$items_json" \
    --argjson current "$current" \
    --argjson snoozed "$enf_snoozed" \
    '{ schema: "soif-freshness/1",
       generatedAt: $gen,
       current: $current,
       enforcementSnoozed: $snoozed,
       toolsCovered: false,
       network: "none",
       items: $items }'
}

# _soif_fresh_iso <epoch> — ISO-8601 UTC. GNU-first then BSD.
_soif_fresh_iso() {
  date -u -d "@$1" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
    || date -u -r "$1" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
    || date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# _soif_fresh_render_human <items_tsv> <enf_snoozed> — the compact tiered human
# block: ENFORCEMENT first ("recommended now"), then informational.
_soif_fresh_render_human() {
  local items="$1" enf_snoozed="$2"
  local enf inf id check tier path verb sig msg
  enf="$(printf '%s\n' "$items" | awk -F'\t' '$3=="enforcement"')"
  inf="$(printf '%s\n' "$items" | awk -F'\t' '$3=="informational"')"
  printf 'FRAMEWORK CURRENCY — updates available. Report to the operator; do NOT auto-apply.\n'
  if [ -n "$(printf '%s' "$enf" | tr -d '[:space:]')" ]; then
    printf '\nRecommended now (enforcement):\n'
    printf '%s\n' "$enf" | while IFS="$(printf '\t')" read -r id check tier path verb sig msg; do
      [ -n "$id" ] || continue
      printf '  - %s\n' "$msg"
    done
  fi
  if [ -n "$(printf '%s' "$inf" | tr -d '[:space:]')" ]; then
    printf '\nInformational:\n'
    printf '%s\n' "$inf" | while IFS="$(printf '\t')" read -r id check tier path verb sig msg; do
      [ -n "$id" ] || continue
      printf '  - %s\n' "$msg"
    done
  fi
  if [ "$enf_snoozed" -gt 0 ]; then
    printf '\n(%s enforcement items snoozed.)\n' "$enf_snoozed"
  fi
}

# ── Orchestration ────────────────────────────────────────────────────────────
# soif_freshness_run <proj_dir> — the normal-path orchestrator the fail-open
# wrapper calls. Resolves paths, detects, filters/prunes snoozes, atomically
# updates the cache, and renders output. Returns 0 on the normal path; nonzero
# ONLY on a genuine internal fault (which the wrapper converts to exit 0).
soif_freshness_run() {
  local proj="$1"

  # Selftest fault hook — exercises the fail-open wrapper (I7). Product-inert
  # unless SOIF_FRESHNESS_SELFTEST_CRASH=1 is explicitly set (never in a session).
  if [ "${SOIF_FRESHNESS_SELFTEST_CRASH:-}" = "1" ]; then
    echo "injected fault (freshness selftest)" >&2
    return 1
  fi

  command -v jq >/dev/null 2>&1 || return 0            # no jq → cannot read manifest → silent
  local mani="$proj/.claude/manifest.json"
  [ -f "$mani" ] || return 0                           # not a scaffolded project → silent
  jq -e '.currency' "$mani" >/dev/null 2>&1 || return 0 # pre-S1 project (no currency block) → silent

  local fw cdf init now cache items
  fw="$(jq -r '.currency.soloFrameworkPath // empty' "$mani" 2>/dev/null)"
  cdf="${CDF_HOME:-$HOME/.claude-dev-framework}"
  init="$fw/init.sh"
  now="$(soif_freshness_now)"
  cache="$proj/.claude/cache/freshness.json"

  items="$(soif_freshness_detect "$proj" "$mani" "$fw" "$init" "$cdf")"

  # Snooze filter + prune (I7 cache). Held snoozes suppress their item; an
  # enforcement snooze also increments the standing count. Only snoozes whose
  # item is still drifting AND still held survive the prune.
  local cache_json enf_snoozed=0 kept_ids_file displayed_file
  cache_json="$(_soif_fresh_cache_read "$cache")"
  kept_ids_file="$(mktemp 2>/dev/null)" || kept_ids_file="${TMPDIR:-/tmp}/soif-fresh-keep.$$"
  displayed_file="$(mktemp 2>/dev/null)" || displayed_file="${TMPDIR:-/tmp}/soif-fresh-disp.$$"
  : > "$kept_ids_file"; : > "$displayed_file"

  local id check tier path verb sig msg
  while IFS="$(printf '\t')" read -r id check tier path verb sig msg; do
    [ -n "$id" ] || continue
    if _soif_fresh_snooze_held "$cache_json" "$id" "$tier" "$sig" "$now"; then
      printf '%s\n' "$id" >> "$kept_ids_file"
      [ "$tier" = "enforcement" ] && enf_snoozed=$(( enf_snoozed + 1 ))
    else
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$check" "$tier" "$path" "$verb" "$sig" "$msg" >> "$displayed_file"
    fi
  done <<< "$items"

  # Rebuild the cache: keep only still-held snoozes for currently-drifting items.
  local keep_json new_cache
  keep_json="$(jq -Rn '[inputs | select(length>0)]' < "$kept_ids_file" 2>/dev/null)"
  [ -n "$keep_json" ] || keep_json='[]'
  new_cache="$(printf '%s' "$cache_json" | jq --argjson keep "$keep_json" --arg now "$now" '
      { schemaVersion: 1,
        updatedAt: ($now|tonumber),
        snoozes: ( (.snoozes // {}) | with_entries(select(.key as $k | $keep | index($k))) ) }' 2>/dev/null)"
  [ -n "$new_cache" ] || new_cache="$(jq -n --arg now "$now" '{schemaVersion:1, updatedAt:($now|tonumber), snoozes:{}}')"
  _soif_fresh_cache_write "$cache" "$new_cache"

  local displayed
  displayed="$(cat "$displayed_file")"
  rm -f "$kept_ids_file" "$displayed_file" 2>/dev/null

  # SILENT when current. Exception (review-r1 M5): the standing snoozed line
  # prints while any enforcement snooze is held, even if otherwise current.
  if [ -z "$(printf '%s' "$displayed" | tr -d '[:space:]')" ]; then
    if [ "$enf_snoozed" -gt 0 ]; then
      printf '%s enforcement items snoozed\n' "$enf_snoozed"
    fi
    return 0
  fi

  # Drift present: one compact human block + one fenced machine block.
  _soif_fresh_render_human "$displayed" "$enf_snoozed"
  printf '\n```soif-freshness\n'
  _soif_fresh_machine_json "$displayed" "$now" "$enf_snoozed"
  printf '\n```\n'
  return 0
}

# ── Snooze setting (out-of-band; NEVER during silent detection) ──────────────
# soif_freshness_snooze <proj_dir> <item-id> — record a snooze for a currently-
# drifting item. Informational snoozes hold until the upstream delta changes;
# enforcement snoozes auto-expire after 7 days AND are recorded through
# scripts/lib/bypass-audit.sh (review-r1 M5). Trivially safe: writes only the
# cache + (for enforcement) an audit row. Returns 1 if the id is not an active
# drift item.
soif_freshness_snooze() {
  local proj="$1" target="$2"
  command -v jq >/dev/null 2>&1 || return 1
  local mani="$proj/.claude/manifest.json"
  [ -f "$mani" ] || return 1

  local fw cdf init now cache items
  fw="$(jq -r '.currency.soloFrameworkPath // empty' "$mani" 2>/dev/null)"
  cdf="${CDF_HOME:-$HOME/.claude-dev-framework}"
  init="$fw/init.sh"
  now="$(soif_freshness_now)"
  cache="$proj/.claude/cache/freshness.json"
  items="$(soif_freshness_detect "$proj" "$mani" "$fw" "$init" "$cdf")"

  local id check tier path verb sig msg _snz_tier="" _snz_sig=""
  while IFS="$(printf '\t')" read -r id check tier path verb sig msg; do
    if [ "$id" = "$target" ]; then _snz_tier="$tier"; _snz_sig="$sig"; break; fi
  done <<< "$items"
  if [ -z "$_snz_tier" ]; then
    printf 'freshness: no active drift item with id "%s" to snooze\n' "$target" >&2
    return 1
  fi

  local cache_json new_cache
  cache_json="$(_soif_fresh_cache_read "$cache")"
  new_cache="$(printf '%s' "$cache_json" | jq \
      --arg id "$target" --arg tier "$_snz_tier" --arg sig "$_snz_sig" --arg now "$now" '
      .schemaVersion = 1
      | .updatedAt = ($now|tonumber)
      | .snoozes = ((.snoozes // {}) + { ($id): { tier:$tier, snoozedAt:($now|tonumber), deltaSig:$sig } })' 2>/dev/null)"
  _soif_fresh_cache_write "$cache" "$new_cache"

  if [ "$_snz_tier" = "enforcement" ]; then
    _soif_fresh_audit_snooze "$proj" "$target" "$now"
  fi
  printf 'freshness: snoozed "%s" (%s tier)\n' "$target" "$_snz_tier"
  return 0
}

# soif_freshness_unsnooze <proj_dir> <item-id> — drop a snooze entry.
soif_freshness_unsnooze() {
  local proj="$1" target="$2"
  command -v jq >/dev/null 2>&1 || return 1
  local cache="$proj/.claude/cache/freshness.json"
  local cache_json new_cache now
  now="$(soif_freshness_now)"
  cache_json="$(_soif_fresh_cache_read "$cache")"
  new_cache="$(printf '%s' "$cache_json" | jq --arg id "$target" --arg now "$now" '
      .schemaVersion = 1 | .updatedAt = ($now|tonumber)
      | .snoozes = ((.snoozes // {}) | del(.[$id]))' 2>/dev/null)"
  _soif_fresh_cache_write "$cache" "$new_cache"
  printf 'freshness: unsnoozed "%s"\n' "$target"
  return 0
}

# _soif_fresh_audit_snooze <proj> <id> <now> — record an enforcement snooze
# through scripts/lib/bypass-audit.sh (review-r1 M5). Mirrors the canonical row
# shape; the `type` value "freshness_enforcement_snooze" EXTENDS the documented
# enum (declared deviation — the append API validates object-shape only, so no
# parallel audit file is invented). Best-effort: never fatal.
_soif_fresh_audit_snooze() {
  local proj="$1" id="$2" now="$3"
  if ! command -v bypass_audit_append >/dev/null 2>&1; then
    local d
    d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=/dev/null
    [ -f "$d/bypass-audit.sh" ] && . "$d/bypass-audit.sh"
  fi
  command -v bypass_audit_append >/dev/null 2>&1 || return 0
  local ts row
  ts="$(_soif_fresh_iso "$now")"
  row="$(jq -nc --arg ts "$ts" --arg id "$id" '
      { timestamp:$ts, session_id:null, type:"freshness_enforcement_snooze", actor:"framework",
        enforcement_level_at_event:"n/a",
        details:{ item_id:$id, ttl_days:7, source:"session-freshness-check --snooze" },
        user_response:"n/a", final_outcome:"recorded_only" }')"
  bypass_audit_append "$proj" "$row" >/dev/null 2>&1 || true
}

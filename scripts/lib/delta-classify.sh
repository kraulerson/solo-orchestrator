#!/usr/bin/env bash
# scripts/lib/delta-classify.sh — the §4.2 derivations for the post-MVP delta
# track: risk, level, severity, the phrase->class PROPOSAL, and the §7.1
# `gates_required` materialisation that §5.2's table describes.
#
# SPEC: docs/designs/2026-08-02-delta-track-v1.md §4.1 (the four classes),
# §4.2 (the derived-then-confirmed attributes and their author-proposed
# formulas), §4.3 (confirm-not-quiz — this file supplies the VALUE and the
# PROVENANCE for every line of that transcript), §5.2 (the per-class gate
# subset + the attribute toggles), §7.2 (every threshold and every gate list is
# READ FROM POLICY, never hardcoded), §3.1 (this file is a member of the
# severable delta module's inventory), §11-WP3.
#
# (No `# BL-NNN-…` marker anywhere in the delta track on purpose — no backlog
# entry exists for this build, and minting one would red
# scripts/lint-bl-markers.sh, whose first pass resolves every marker to a real
# `## BL-NNN:` entry. The design-doc path above is the citation, per the WP1 and
# WP2 precedent. The grep-able `DELTA-CLASSIFY-*` markers below are this file's
# citation primitive and its mutation addresses.)
#
# ── EVERY FUNCTION HERE PROPOSES; NOTHING HERE DECIDES ───────────────────────
# D2 is explicit that the class is "auto-proposed from the user's phrasing where
# possible and CONFIRMED, never quizzed". So each derivation returns two things
# on one line, TAB-separated:
#
#     <value><TAB><provenance>
#
# The provenance half is not decoration and it is not a log line: §4.3 requires
# that "every one of the four lines names WHERE THE VALUE CAME FROM, because a
# proposal whose provenance is hidden is a quiz with extra steps." Returning the
# pair together is what makes it impossible to render the value without its
# reason — a two-call API (value here, reason there) would let a caller print
# the number and drop the sentence, which is exactly the failure §4.3 names.
# Callers split with `cut -f1` / `cut -f2-`.
#
# ── THE TWO HONEST LIMITS (§4.2), RESTATED WHERE THEY BITE ───────────────────
#   1. DERIVATION AT OPEN TIME IS A FORECAST. At `--open` the diff is usually
#      empty, so `risk` and `level` are proposals from the STATED intent. §4.2
#      re-derives them at close and RATCHETS (raise only). This file computes
#      the same way at both moments; it does not know which moment it is in, and
#      it must not — the ratchet is WP4's, applied to these outputs.
#   2. `risk_surfaces` IS A PROJECT-AUTHORED GLOB LIST and ships EMPTY (§7.2).
#      An empty list makes every delta `feature-local`, forever, silently. That
#      is §13-R4, and delta_classify_risk states it in its own provenance string
#      rather than quietly answering "feature-local" as though it had looked.
#
# ── LINES ARE A POOR PROXY, ON PURPOSE (§7.2) ────────────────────────────────
# A 12-line auth change is riskier than a 900-line locale file. That is exactly
# why risk is a SEPARATE axis derived from PATHS, and why the operator may raise
# either freely (§4.2). Do not "improve" the level formula into a risk formula.
#
# ── POLICY IS READ, NEVER HARDCODED ──────────────────────────────────────────
# Every threshold, every gate list and every toggle comes from
# delta_policy_get, which falls back per KEY to the framework defaults (§3.2).
# The literal numbers that appear below are LAST-RESORT fallbacks for the case
# where the policy layer itself is unavailable, and each one sits on a line whose
# marker is a mutation address: neuter the read and the policy-retune tests go
# RED. That is the pin that keeps a "temporary" hardcode from surviving.
#
# DEPENDENCY DIRECTION (D1)
#   delta -> core is allowed and unasserted. core -> delta is forbidden and
#   lint-enforced by scripts/lint-delta-boundary.sh with ONE allowlisted seam.
#   This file sources a SIBLING delta lib (delta -> delta), which the lint does
#   not scan at all; nothing in core may source this file.
#
# BASH 3.2 COMPATIBILITY
#   macOS ships bash 3.2.57. No associative arrays, no ${var,,} (hence the
#   `tr` lowering below), no `((x++))`, no nullglob. Every function is
#   errexit-safe: this lib is sourced into scripts/delta.sh, which runs under
#   `set -euo pipefail`, so no bare command is left to fail on its own.

# The policy reader is a hard dependency and a delta -> delta edge, so sourcing
# it here is free of boundary consequences. Guarded so a caller that already
# sourced it does not pay twice.
if ! command -v delta_policy_get >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/delta-policy.sh"
fi

# ─────────────────────────────────────────────────────────────────────────────
# THE TOUCHED-FILE SET AND THE DIFF SIZE
# ─────────────────────────────────────────────────────────────────────────────

# _delta_classify_base <project_root>
#   Echo the merge base to diff against, or nothing. §4.2 says "against the
#   merge base"; which ref that is depends on the project, so the candidates are
#   tried in order and the first that resolves wins. DELTA_BASE_REF overrides
#   for a project whose trunk is named something else — and for tests, which
#   must not depend on what the host's git happens to have.
#
#   NOTHING is an entirely normal answer: at `--open` on trunk the merge base IS
#   HEAD, the diff is empty, and §4.2's "derivation at open time is a forecast"
#   is the whole point. A missing base must therefore never be an error.
_delta_classify_base() {
  local root="${1:-.}" ref base=""
  command -v git >/dev/null 2>&1 || return 0
  git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || return 0
  for ref in "${DELTA_BASE_REF:-}" origin/HEAD origin/main origin/master main master; do
    [ -n "$ref" ] || continue
    git -C "$root" rev-parse --verify --quiet "$ref" >/dev/null 2>&1 || continue
    base="$(git -C "$root" merge-base HEAD "$ref" 2>/dev/null)" || base=""
    [ -n "$base" ] && break
  done
  [ -n "$base" ] && printf '%s\n' "$base"
  return 0
}

# delta_classify_touched <project_root>
#   The touched-file set, one path per line, sorted and de-duplicated. §4.2's
#   `git diff --name-only against the merge base`, widened to include the
#   working tree and the index — a delta is usually opened with work already in
#   progress, and a formula that only looked at committed history would answer
#   "nothing touched" for exactly the operator who has the most to declare.
#   Always rc 0: a non-git directory has an empty touched set, not an error.
delta_classify_touched() {
  local root="${1:-.}" base
  command -v git >/dev/null 2>&1 || return 0
  git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || return 0
  base="$(_delta_classify_base "$root")"
  {
    if [ -n "$base" ]; then git -C "$root" diff --name-only "$base" 2>/dev/null || true; fi
    git -C "$root" diff --name-only 2>/dev/null || true
    git -C "$root" diff --name-only --cached 2>/dev/null || true
  } | sed '/^$/d' | LC_ALL=C sort -u
  return 0
}

# delta_classify_lines <project_root>
#   Changed lines (insertions + deletions) from `git diff --shortstat`, per
#   §4.2. Prints a bare integer, always rc 0 — `0` for a non-git tree or an
#   empty diff, which is the forecast case and not a failure.
delta_classify_lines() {
  local root="${1:-.}" base stat="" ins=0 del=0 n
  if ! command -v git >/dev/null 2>&1 || ! git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    printf '0\n'; return 0
  fi
  base="$(_delta_classify_base "$root")"
  if [ -n "$base" ]; then
    stat="$(git -C "$root" diff --shortstat "$base" 2>/dev/null)" || stat=""
  fi
  if [ -z "$stat" ]; then
    stat="$(git -C "$root" diff --shortstat 2>/dev/null)" || stat=""
  fi
  n="$(printf '%s' "$stat" | grep -o '[0-9][0-9]* insertion' | grep -o '[0-9][0-9]*' || true)"
  case "$n" in ''|*[!0-9]*) ins=0 ;; *) ins="$n" ;; esac
  n="$(printf '%s' "$stat" | grep -o '[0-9][0-9]* deletion' | grep -o '[0-9][0-9]*' || true)"
  case "$n" in ''|*[!0-9]*) del=0 ;; *) del="$n" ;; esac
  printf '%s\n' "$((ins + del))"
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# RISK — the touched-file set intersected with the policy's risk surfaces
# ─────────────────────────────────────────────────────────────────────────────

# delta_classify_risk_matches <project_root> <touched-file-list-file>
#   One `path<TAB>glob` line per intersection. §4.2 requires the confirmation be
#   "shown with the MATCHING PATHS NAMED", so the caller needs the pairs and not
#   just a count.
#
#   Matching is bash `case` pattern matching, which is deliberately NOT
#   path-aware: `*` crosses `/`. That makes `src/auth/**` match
#   `src/auth/x/y.ts` (what a project author means) and `**/schema*` match
#   `db/schema.sql` (likewise). The known consequence is that a leading `**/`
#   still requires at least one `/` in the path, so a root-level `schema.sql`
#   does NOT match `**/schema*` — write `schema*` as a second glob if you want
#   both. Stated rather than smoothed; a glob list the framework silently
#   reinterpreted would be worse than one the operator can read.
delta_classify_risk_matches() {
  local root="${1:-.}" files="${2:-}" surfaces globs path g
  [ -n "$files" ] && [ -f "$files" ] || return 0
  surfaces="$(delta_policy_get "$root" "risk_surfaces")" || surfaces="[]"   # DELTA-CLASSIFY-RISK-SURFACES
  globs="$(mktemp)" || return 0
  printf '%s\n' "$surfaces" | jq -r '.[]? | select(type == "string")' > "$globs" 2>/dev/null || : > "$globs"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    while IFS= read -r g; do
      [ -n "$g" ] || continue
      # Unquoted on purpose: in pattern position an unquoted expansion IS the
      # glob. Quoting it here would turn every risk surface into a literal
      # string compare and silently answer "feature-local" for every project.
      case "$path" in
        $g) printf '%s\t%s\n' "$path" "$g" ;;
      esac
    done < "$globs"
  done < "$files"
  rm -f "$globs" 2>/dev/null || true
  return 0
}

# delta_classify_risk <project_root> <touched-file-list-file>
#   `core` iff the intersection is non-empty, else `feature-local` (§4.2), plus
#   the provenance §4.3 prints.
#
#   §13-R4, NAMED IN THE OUTPUT AND NOT ONLY IN A COMMENT. `risk_surfaces` ships
#   EMPTY (§7.2), and an empty list makes EVERY delta feature-local for as long
#   as nobody fills it. The framework cannot compute the right list — it is the
#   project's threat model — so the honest move is to say so on the line the
#   operator is being asked to confirm, rather than answering "feature-local" in
#   a tone that implies something was checked. That distinct provenance string
#   is the mitigation §13-R4 gets; it is not a cure.
delta_classify_risk() {
  local root="${1:-.}" files="${2:-}" surfaces count matches first_path first_glob n
  surfaces="$(delta_policy_get "$root" "risk_surfaces")" || surfaces="[]"
  count="$(printf '%s\n' "$surfaces" | jq -r 'if type == "array" then length else 0 end' 2>/dev/null)" || count=0
  case "$count" in ''|*[!0-9]*) count=0 ;; esac
  if [ "$count" -eq 0 ]; then
    printf 'feature-local\tno risk surfaces are configured yet, so nothing can match — every change reads as feature-local until someone lists this project'"'"'s sensitive paths\n'
    return 0
  fi
  matches="$(delta_classify_risk_matches "$root" "$files")" || matches=""
  if [ -z "$matches" ]; then
    printf 'feature-local\tnone of the files touched so far match any of the %s configured risk surface(s)\n' "$count"
    return 0
  fi
  n="$(printf '%s\n' "$matches" | grep -c '' || true)"
  case "$n" in ''|*[!0-9]*) n=1 ;; esac
  first_path="$(printf '%s\n' "$matches" | sed -n '1p' | cut -f1)"
  first_glob="$(printf '%s\n' "$matches" | sed -n '1p' | cut -f2)"
  if [ "$n" -gt 1 ]; then
    printf 'core\t%s touched file(s) match a risk surface — e.g. %s matches the pattern %s\n' "$n" "$first_path" "$first_glob"
  else
    printf 'core\tthe touched file %s matches the risk surface pattern %s\n' "$first_path" "$first_glob"
  fi
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# LEVEL — changed lines against the policy's size thresholds
# ─────────────────────────────────────────────────────────────────────────────

# delta_classify_level <project_root> <changed-lines>
#   §4.2's bracket: below `small` => small; below `significant` => significant;
#   at or above => evolution.
#
#   BOTH THRESHOLDS ARE READ FROM POLICY. The literals on the fallback halves of
#   those two lines exist only for the case where the policy layer itself cannot
#   answer, and each line carries a marker so a counterfactual can neuter
#   EXACTLY ONE of them: with the read gone, a project that retuned
#   `size_thresholds` keeps getting the framework bracket and nothing else
#   changes — no error, no warning, just a wrong answer. That is precisely the
#   defect the retune test + its mutation exist to make loud.
delta_classify_level() {
  local root="${1:-.}" lines="${2:-0}" small significant
  case "$lines" in ''|*[!0-9]*) lines=0 ;; esac
  small="$(delta_policy_get "$root" "size_thresholds.small")" || small=50                        # DELTA-CLASSIFY-LEVEL-SMALL
  significant="$(delta_policy_get "$root" "size_thresholds.significant")" || significant=400     # DELTA-CLASSIFY-LEVEL-SIGNIFICANT
  case "$small" in ''|*[!0-9]*) small=50 ;; esac
  case "$significant" in ''|*[!0-9]*) significant=400 ;; esac
  if [ "$lines" -lt "$small" ]; then
    printf 'small\t%s changed line(s) so far, under this project'"'"'s small threshold of %s; re-measured from the real diff when the delta closes\n' "$lines" "$small"
  elif [ "$lines" -lt "$significant" ]; then
    printf 'significant\t%s changed line(s) so far, at or over %s and under %s (this project'"'"'s thresholds); re-measured at close\n' "$lines" "$small" "$significant"
  else
    printf 'evolution\t%s changed line(s) so far, at or over this project'"'"'s evolution threshold of %s; re-measured at close\n' "$lines" "$significant"
  fi
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# CLASS — the phrase -> class PROPOSAL (§4.1/§4.3)
# ─────────────────────────────────────────────────────────────────────────────

# delta_classify_class <phrase>
#   Four ordered keyword tiers, most-consequential first. Deliberately simple
#   and transparent: it is a PROPOSAL the operator confirms in one keystroke,
#   never a decision, so a cleverer classifier would buy accuracy the operator
#   cannot audit at the cost of an explanation they can. §13-R9 records the
#   thing that would change this: if the proposal is wrong often enough the
#   confirm step becomes the quiz D2 rejected, and the fix is BETTER TIERS, not
#   a second question.
#
#   ORDER IS THE WHOLE ALGORITHM. "a security fix for the production outage"
#   contains all three lower tiers; security wins because a security-patch's
#   obligations (dependency scan, SBOM, flagged note) are the ones most costly
#   to discover you skipped. Ties never happen — the first matching tier returns.
delta_classify_class() {
  local phrase="${1:-}" p
  p="$(printf '%s' "$phrase" | tr '[:upper:]' '[:lower:]')"
  case "$p" in
    *security*|*vulnerab*|*cve-*|*exploit*|*xss*|*csrf*|*injection*|*cvss*|*attacker*|*"auth bypass"*|*"privilege escalation"*|*"leaks credentials"*)
      printf 'security-patch\tproposed from your wording, which names a security concern — a security-patch is a fix plus a dependency scan, an SBOM refresh and a flagged release note\n' ;;
    *hotfix*|*production*|*outage*|*"in prod"*|*urgent*|*emergency*|*"right now"*|*"is down"*|*"are down"*)
      printf 'hotfix\tproposed from your wording, which says this is live and now — a hotfix ships fast and owes a retro within days; a fix waits for the normal loop\n' ;;
    *fix*|*broken*|*breaks*|*crash*|*bug*|*fail*|*error*|*regress*|*wrong*|*incorrect*|*"does not work"*|*"doesn't work"*|*throws*|*hang*|*corrupt*)
      printf 'fix\tproposed from your wording — a fix is something broken that can wait for the normal loop; a hotfix is production, now\n' ;;
    *)
      printf 'feature\tproposed from your wording, which describes something new rather than something broken — a feature gets the full ceremony\n' ;;
  esac
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# SEVERITY — the BUGS.md row if one is referenced, else the Severity Guide
# ─────────────────────────────────────────────────────────────────────────────

# _delta_classify_bug_ref <phrase>
#   The bare integer of a referenced bug, or nothing. `BUG-12`, `bug 12` and
#   `bug #12` are all the shipped citation spellings (templates/generated/
#   bugs.tmpl: "Cite bugs elsewhere as BUG-<#>, the # column, bare integer").
_delta_classify_bug_ref() {
  local p
  p="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  printf '%s' "$p" | sed -n 's/.*bug[-# ]*\([0-9][0-9]*\).*/\1/p' | sed -n '1p'
  return 0
}

# _delta_classify_bug_severity <project_root> <bug-number>
#   The Severity cell of that row of BUGS.md, or nothing. The tracker's column
#   order is fixed by the template's own "Do NOT change the table format" note
#   and is already parsed by scripts/test-gate.sh, so reading columns 2 and 3
#   here is the shipped grammar and not a new one.
_delta_classify_bug_severity() {
  local root="${1:-.}" num="${2:-}" f
  f="${root%/}/BUGS.md"
  case "$f" in ./*) f="${f#./}" ;; esac
  [ -f "$f" ] || return 0
  [ -n "$num" ] || return 0
  awk -F'|' -v want="$num" '
    /^[[:space:]]*\|/ {
      id = $2; sev = $3
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", sev)
      gsub(/\*/, "", sev)
      if (id == want && sev ~ /^SEV-[1-4]$/) { print sev; exit }
    }' "$f" 2>/dev/null || true
  return 0
}

# delta_classify_severity <project_root> <class> <phrase>
#   §4.2: "Proposed from the BUGS.md row if one exists, else from phrasing
#   against the shipped Severity Guide's own definitions in
#   templates/generated/bugs.tmpl". fix / hotfix / security-patch ONLY — a
#   feature has no severity, and this returns an EMPTY value with a provenance
#   that says why, so §4.3's transcript can still print four lines.
#
#   The keyword sets below are lifted from the Severity Guide's own Definition
#   and Examples columns, so a project that edits its guide and its rows stays
#   coherent with what this proposes. The per-class default at the end is the
#   Guide read literally: a security concern IS the Guide's SEV-1 "security
#   breach" row; a production outage IS its "app crash on core flow"; and an
#   ordinary break with a workaround is its SEV-2.
delta_classify_severity() {
  local root="${1:-.}" class="${2:-}" phrase="${3:-}" p num sev
  case "$class" in
    fix|hotfix|security-patch) : ;;
    *)
      printf '\tnot applicable — severity is a fix, hotfix or security-patch attribute (§4.2); a feature does not carry one\n'
      return 0 ;;
  esac

  num="$(_delta_classify_bug_ref "$phrase")"
  if [ -n "$num" ]; then
    sev="$(_delta_classify_bug_severity "$root" "$num")"
    if [ -n "$sev" ]; then
      printf '%s\tread from the BUG-%s row already in BUGS.md — the tracker is the record, this is not a second opinion\n' "$sev" "$num"
      return 0
    fi
  fi

  p="$(printf '%s' "$phrase" | tr '[:upper:]' '[:lower:]')"
  case "$p" in
    *"data loss"*|*"security breach"*|*"auth bypass"*|*corrupt*|*"cannot log in"*|*"can't log in"*|*"crash on login"*|*"nobody can"*|*"no one can"*|*"loses data"*|*"losing data"*)
      printf 'SEV-1\tmatched the Severity Guide'"'"'s SEV-1 definition in BUGS.md (data loss, security breach, or a crash on a core flow) — SEV-1 cannot be deferred\n' ;;
    *"workaround"*|*"broken but"*|*"wrong data"*|*"layout broken"*|*"significant"*)
      printf 'SEV-2\tmatched the Severity Guide'"'"'s SEV-2 definition in BUGS.md (feature broken, workaround exists)\n' ;;
    *minor*|*cosmetic*|*alignment*|*tooltip*|*"edge case"*|*typo*)
      printf 'SEV-3\tmatched the Severity Guide'"'"'s SEV-3 definition in BUGS.md (minor UX, cosmetic, non-core edge case)\n' ;;
    *"would be nice"*|*enhancement*|*polish*|*"nice to have"*|*optimi*)
      printf 'SEV-4\tmatched the Severity Guide'"'"'s SEV-4 definition in BUGS.md (enhancement, suggestion, polish)\n' ;;
    *)
      case "$class" in
        security-patch)
          printf 'SEV-1\tno severity wording matched, so this defaults to the Severity Guide'"'"'s SEV-1 row, which is where a security breach sits\n' ;;
        hotfix)
          printf 'SEV-1\tno severity wording matched, so this defaults to the Severity Guide'"'"'s SEV-1 row — a hotfix is a live break on a core flow\n' ;;
        *)
          printf 'SEV-2\tno severity wording matched, so this defaults to the Severity Guide'"'"'s SEV-2 row (feature broken, workaround exists)\n' ;;
      esac ;;
  esac
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# gates_required — MATERIALISED AT OPEN (§7.1) FROM CLASS + CONFIRMED ATTRIBUTES
# ─────────────────────────────────────────────────────────────────────────────

# delta_classify_gates <project_root> <class> <risk> <level>
#   A compact JSON array: the class's base row from `classes.<class>.gates`
#   (§5.2), then the attribute toggles §5.2's right-hand column names —
#   `risk: core` adds `attribute_toggles.risk_core`, `level: evolution` adds
#   `attribute_toggles.level_evolution`. rc 1 on an unknown class, so a typo can
#   never materialise an EMPTY gate set (which would be a delta with no
#   obligations that looked exactly like a well-formed one).
#
#   MATERIALISED, NOT RECOMPUTED (§7.1). The result is written into the state
#   document at open and never re-derived at close: recomputing "would let a
#   policy edit mid-delta silently drop a gate the operator had already been told
#   about". Attribute RAISES append to it (WP4); nothing ever removes from it.
#
#   `touch_trigger` is deliberately NOT applied here. It is a §8.1 re-fire
#   trigger keyed on what gets touched during the work, not an attribute
#   confirmed at open, and WP6 owns it. Materialising it now would put a gate on
#   the row before anything had triggered it.
#
#   ORDER-PRESERVING DE-DUPLICATION, not `unique`. `unique` sorts, and the base
#   row's order is §5.2's reading order; a sorted row is the same SET and a worse
#   checklist. A toggle that names a gate the class already carries is a no-op
#   rather than a duplicate — which is exactly what happens for a `feature` at
#   `risk: core`, since `brief_review` is already in the feature row.
delta_classify_gates() {
  local root="${1:-.}" class="${2:-}" risk="${3:-}" level="${4:-}"
  local base toggle_core="[]" toggle_evo="[]" out
  if [ -z "$class" ]; then
    printf '%s\n' "delta-classify: a class is required to materialise gates_required" >&2
    return 1
  fi
  if ! base="$(delta_policy_get "$root" "classes.$class.gates")"; then
    printf '%s\n' "delta-classify: no gate list for class '$class' — the four classes are feature, fix, hotfix and security-patch (§4.1). Nothing was materialised." >&2
    return 1
  fi
  toggle_core="$(delta_policy_get "$root" "attribute_toggles.risk_core")" || toggle_core="[]"            # DELTA-CLASSIFY-TOGGLE-RISKCORE
  toggle_evo="$(delta_policy_get "$root" "attribute_toggles.level_evolution")" || toggle_evo="[]"        # DELTA-CLASSIFY-TOGGLE-LEVELEVO
  if ! out="$(jq -c -n \
      --argjson base "$base" --argjson tc "$toggle_core" --argjson te "$toggle_evo" \
      --arg risk "$risk" --arg level "$level" '
        (( $base // [] )
         + (if $risk  == "core"      then ($tc // []) else [] end)
         + (if $level == "evolution" then ($te // []) else [] end))
        | map(select(type == "string"))
        | reduce .[] as $g ([]; if (index($g) != null) then . else . + [$g] end)
      ' 2>/dev/null)"; then
    printf '%s\n' "delta-classify: could not materialise gates_required for class '$class'. Nothing was materialised." >&2
    return 1
  fi
  printf '%s\n' "$out"
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# THE GATE-TOKEN VOCABULARY (§5.2) — what the close gate validates against
# ─────────────────────────────────────────────────────────────────────────────

# delta_classify_gate_vocabulary <project_root>
#   Every gate token this project can legitimately carry, one per line, sorted
#   and de-duplicated. Always rc 0.
#
#   WHY THIS IS A UNION AND NOT §5.2's TABLE. The obvious implementation is the
#   thirteen tokens of §5.2, compiled in. It is wrong, and the repo already
#   proves it wrong: tests/test-delta-wp3-era-classify.sh::G4 pins that a
#   project may retune `attribute_toggles.risk_core` to `["second_reviewer"]`
#   and get ITS gate materialised (§7.2 — "every key is overridable"). A close
#   gate holding that project's own token against a framework table would
#   refuse every close it ever attempts, and the operator's only escape would be
#   to un-retune the policy the framework told them was theirs.
#
#   So the vocabulary is the UNION of two things:
#     • THE FRAMEWORK FLOOR — §5.2's table, spelled out below. It is here so a
#       project whose policy file omits a class row (or omits `classes`
#       entirely) still recognises the tokens the framework's own defaults can
#       produce, and so the floor is greppable from one place.
#     • THE RESOLVED POLICY — every string under `classes.*.gates` and under
#       `attribute_toggles.*`, read through delta_policy_get so a project value
#       wins per key and an absent key falls back (§3.2).
#
#   WHAT IS STILL REFUSED, which is the point: a token that appears in NEITHER.
#   That is a hand-edited state file or a typo in a policy edit — `close_reviw`
#   would otherwise become a gate that can never be completed and never be
#   questioned, because nothing else in the system reads these strings. It fails
#   CLOSED at the close gate, named, which is the only place the operator is
#   still able to act on it.
delta_classify_gate_vocabulary() {
  local root="${1:-.}" classes toggles
  classes="$(delta_policy_get "$root" "classes")" || classes="{}"                    # DELTA-CLASSIFY-VOCAB-CLASSES
  toggles="$(delta_policy_get "$root" "attribute_toggles")" || toggles="{}"          # DELTA-CLASSIFY-VOCAB-TOGGLES
  {
    # §5.2's table, read top to bottom. THE FRAMEWORK FLOOR.
    printf '%s\n' \
      brief brief_review ledger_row build_loop repro_test_red_first \
      audit_row_at_open retro_review threat_model_refresh dependency_scan \
      sbom_refresh flagged_release_note close_review changelog
    printf '%s\n' "$classes" | jq -r '.[]?.gates[]? | select(type == "string")' 2>/dev/null || true
    printf '%s\n' "$toggles" | jq -r '.[]?[]? | select(type == "string")' 2>/dev/null || true
  } | sed '/^$/d' | LC_ALL=C sort -u
  return 0
}

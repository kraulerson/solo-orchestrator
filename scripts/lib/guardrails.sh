# scripts/lib/guardrails.sh — `## BL-320:` Solo Orchestrator's side of the
# Development Guardrails (CDF, ~/.claude-dev-framework) 4.4.0 approval
# design B, and the other places Solo meets the Guardrails' version.
#
# WHAT 4.4.0 CHANGED. A commit is approved only by the USER answering a
# question recorded in .claude/pending-approval.json with an option id — the
# Guardrails' record-approval.sh (a UserPromptSubmit hook) shows the question,
# each option's effect and the staged change on the first reply, and takes the
# pick on the second. The question must be "schema 2" (CDF spec
# docs/superpowers/specs/2026-10-05-approval-via-pending-question-design.md,
# D1): options are {id, text, approves}, ids are a letter and one or two digits
# and unique ignoring case, `approves` is "commit" or "none", and at least one
# option approves nothing. Below 4.4.0 the agent approves its own commits
# (mark-evaluated.sh) and the schema does not matter.
#
# WHAT LIVES HERE (one copy, sourced by every Solo script that needs it):
#   SOIF_GUARDRAILS_MIN            the minimum Guardrails version this
#                                  framework requires (`## BL-375:` 4.6.0: the
#                                  fail-closed hook policy and runaway scan)
#   SOIF_GUARDRAILS_PICK_MIN       the version where answering by option id
#                                  arrived (4.4.0, approval design B); it never
#                                  moves — the two constants below say why
#   soif_gr_route ROOT             pick | legacy | unknown — how a question in
#                                  ROOT is answered, from its manifest
#   soif_pa_v2_problems FILE       CDF's rules for a schema-2 question
#   soif_pa_option_lines FILE      each option and its effect, either schema
#   soif_cdf_register_hooks ROOT CLONE [check]
#                                  the Guardrails hook entries ROOT's manifest
#                                  activates but .claude/settings.json lacks
#                                  (Karl's c2, 2026-10-06): added whole, never
#                                  removed or reordered; a Guardrails entry
#                                  already there has its own timeout and
#                                  onFailure refreshed (`## BL-375:`)
#   soif_guardrails_clone_update CLONE NONINTERACTIVE
#                                  init.sh's ask-first update of the shared
#                                  clone (needs helpers-core.sh's print_* and
#                                  prompt_yes_no)
#
# Shipped to every project (init.sh `# BL-320-SHIP`). bash 3.2 safe; needs jq.
# shellcheck shell=bash

# Two numbers, two jobs — deliberately not one (`## BL-375:`, Karl's ruling B,
# 2026-11-16). SOIF_GUARDRAILS_MIN is the floor this framework REQUIRES: the
# session-start row (check-versions.sh _cv_gr_minimum_rows), the adoption note
# (adopt-guardrails.sh _adopt_guardrails_min_note) and the clone-update warning
# (soif_guardrails_clone_update, below) name a project or clone below it, and
# it moves with what the framework needs from a release — 4.6.0 for the
# fail-closed hook policy (4.5.0) and the runaway scan (4.6.0).
# SOIF_GUARDRAILS_PICK_MIN is the version where approval design B arrived — the
# user answers a question by option id and the Guardrails record the pick — and
# it never moves: soif_gr_route, soif_gr_mixed and pending-approval.sh's
# messages read it. Measured before the split: raising the one constant to
# 4.6.0 routed every 4.4.x/4.5.x project to `legacy`, which accepts the agent's
# own `--resolve --decision` again (pending-approval.sh cmd_resolve) and stops
# refusing a 4.4/4.5 mixed install — an enforcement regression on every host
# that had not updated yet.
SOIF_GUARDRAILS_MIN="4.6.0"   # BL-375-MIN-460
SOIF_GUARDRAILS_PICK_MIN="4.4.0"   # BL-375-PICK-MIN

# soif_gr_xyz_valid V — MAJOR.MINOR.PATCH, digits only, at most nine per part
# (inside `[`'s integer range). The same rule as check-versions.sh's G5 row.
soif_gr_xyz_valid() {
  local re='^[0-9]{1,9}\.[0-9]{1,9}\.[0-9]{1,9}$'
  [[ "${1:-}" =~ $re ]]
}

# soif_gr_xyz_cmp A B — lt, eq or gt, numerically, part by part. Both valid.
soif_gr_xyz_cmp() {
  local i x y
  local -a av=() bv=()
  IFS='.' read -r -a av <<< "$1" || :
  IFS='.' read -r -a bv <<< "$2" || :
  for i in 0 1 2; do
    x="${av[$i]}"; y="${bv[$i]}"
    if [ "$x" -lt "$y" ]; then echo lt; return 0; fi
    if [ "$x" -gt "$y" ]; then echo gt; return 0; fi
  done
  echo eq
}

# soif_gr_below_min V — true when V is a version and is older than the required
# minimum (SOIF_GUARDRAILS_MIN).
soif_gr_below_min() {
  soif_gr_xyz_valid "${1:-}" && [ "$(soif_gr_xyz_cmp "$1" "$SOIF_GUARDRAILS_MIN")" = lt ]   # BL-375-FLOOR-BELOW
}

# soif_gr_below_pick_min V — true when V is a version older than the one where
# answering by option id arrived (SOIF_GUARDRAILS_PICK_MIN; `## BL-375:` the
# pick floor, not the required floor).
soif_gr_below_pick_min() {
  soif_gr_xyz_valid "${1:-}" && [ "$(soif_gr_xyz_cmp "$1" "$SOIF_GUARDRAILS_PICK_MIN")" = lt ]   # BL-375-PICK-BELOW
}

# soif_gr_installed_version ROOT — ROOT's .claude/manifest.json frameworkVersion.
soif_gr_installed_version() {
  jq -r '(.frameworkVersion // empty) | tostring' "$1/.claude/manifest.json" 2>/dev/null || :
}

# soif_gr_route ROOT — how a question in ROOT is answered:
#   pick    Guardrails at or above SOIF_GUARDRAILS_PICK_MIN (4.4.0, where
#           answering by option id arrived — the pick floor, never the required
#           floor, `## BL-375:`): the user replies with the option id, twice,
#           and the Guardrails record the pick
#   legacy  an older version: the user answers in words; the agent clears the
#           question and records the approval itself
#   unknown no readable version (no manifest, no Guardrails, a stub)
soif_gr_route() {
  local v="" c=""
  v="$(soif_gr_installed_version "${1:-.}")"
  soif_gr_xyz_valid "$v" || { echo unknown; return 0; }
  c="$(soif_gr_xyz_cmp "$v" "$SOIF_GUARDRAILS_PICK_MIN")"   # BL-375-PICK-ROUTE
  [ "$c" = lt ] && { echo legacy; return 0; }   # BL-320-ROUTE
  echo pick
}

# soif_gr_writer_schema ROOT — the oldest question schema ROOT's own writers
# produce. Solo has two: scripts/pending-approval.sh (`# BL-320-PA-SCHEMA-MARK`)
# and scripts/hooks/bypass-detector.sh. Each says which schema it writes on a
# line that STARTS `SOIF_APPROVAL_SCHEMA=<n>`; a writer without that line
# predates BL-320 and writes "A1: text" strings, so it counts as 1. Prints the
# smallest number over the writers present, or none when neither is there (no
# Solo writer: nothing to mix). Read from the files, never guessed; compared as
# a number, so a later schema 3 counts as current, not as old.
soif_gr_writer_schema() {
  local root="${1:-.}" f n min=""
  local -a files=("$root/scripts/pending-approval.sh")
  files+=("$root/scripts/hooks/bypass-detector.sh")   # BL-320-WRITER-DETECTOR
  for f in "${files[@]}"; do
    [ -f "$f" ] || continue
    n="$(sed -n 's/^SOIF_APPROVAL_SCHEMA=\([0-9][0-9]*\).*/\1/p' "$f" | head -1)"   # BL-320-WRITER-ANCHOR
    [ -n "$n" ] || n=1
    if [ -z "$min" ] || [ "$n" -lt "$min" ]; then min="$n"; fi
  done
  printf '%s\n' "${min:-none}"
}

# soif_gr_mixed ROOT VERSION — true when installing Guardrails VERSION (at or
# above SOIF_GUARDRAILS_PICK_MIN — the pick floor, `## BL-375:`) in ROOT would
# leave a writer they cannot take an answer from: the mixed install
# `## BL-320:` exists to prevent. Both halves must move together, by the
# framework sync.
soif_gr_mixed() {
  local w=""
  soif_gr_xyz_valid "${2:-}" && ! soif_gr_below_pick_min "$2" || return 1   # BL-375-PICK-MIXED
  w="$(soif_gr_writer_schema "$1")"
  [ "$w" != none ] && [ "$w" -lt 2 ]   # BL-320-WRITER-NUM
}

# soif_gr_git_noprompt [-C DIR] ARGS… — git that cannot stop to ask: no
# credential prompt (GIT_TERMINAL_PROMPT=0) and, unless the user set their own
# ssh command (GIT_SSH_COMMAND, GIT_SSH, or core.sshCommand — measured: each is
# left as it is), ssh in BatchMode, so a passphrase or an unknown host key
# fails instead of waiting. Review round 1, R-7d.
soif_gr_git_noprompt() {
  local dir="."
  [ "${1:-}" = -C ] && dir="${2:-.}"
  if [ -z "${GIT_SSH_COMMAND:-}" ] && [ -z "${GIT_SSH:-}" ] && ! git -C "$dir" config --get core.sshCommand >/dev/null 2>&1; then
    GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes' git "$@"   # BL-320-SSH-BATCH
    return
  fi
  GIT_TERMINAL_PROMPT=0 git "$@"
}

# soif_pa_schema FILE — 2 for a schema-2 question, 1 for any other JSON object,
# 0 for anything else (not JSON, not an object, unreadable).
soif_pa_schema() {
  jq -r 'if type == "object" and .schema == 2 then 2 elif type == "object" then 1 else 0 end' "$1" 2>/dev/null || echo 0
}

# soif_pa_v2_problems FILE — one line per reason the Guardrails could not take
# an answer to FILE; nothing when they can. The rules are CDF 4.4.0's own
# (hooks/_helpers.sh pending_approval_info), restated so Solo can refuse before
# writing rather than after the user has replied twice.
soif_pa_v2_problems() {
  jq -r '
    def idok: type == "string" and test("^[A-Za-z][0-9]{1,2}$");
    if type != "object" or .schema != 2 then "it is not schema 2"
    else
      { question: (if (.question | type) == "string" then .question else "" end),
        opts: [ (.options // [])[]? | { id: (.id // "" | tostring),
                                         approves: (if .approves == "commit" then "commit" else "none" end) } ] }
      | [ (if .question == "" then "the question is empty" else empty end),
          (if (.opts | length) < 2 then "it has fewer than two options" else empty end),
      (if any(.opts[]; (.id | idok) | not) then "an option id is not a letter and one or two digits (A1)" else empty end),   # BL-320-V2-ID
      (if ([.opts[].id | ascii_upcase] | unique | length) != (.opts | length) then "option ids repeat (ignoring case)" else empty end),   # BL-320-V2-UNIQUE
      (if any(.opts[]; .approves == "none") | not then "no option approves nothing" else empty end)   # BL-320-V2-NONE
        ] | .[]
    end' "$1" 2>/dev/null || echo "it is not valid JSON"
}

# soif_pa_option_lines FILE — one line per option. Schema 2 says what picking it
# does; schema 1 is shown as written.
soif_pa_option_lines() {
  jq -r 'if type == "object" and .schema == 2 then (.options // [])[] | "\(.id // "?") — \(.text // "") [\(if .approves == "commit" then "approves committing the staged change" else "approves nothing" end)]" else (.options // [])[]? | tostring end' "$1" 2>/dev/null   # BL-320-PA-LINES
}

# soif_gr_sha256 FILE — the sha256 the Guardrails bind a question to.
soif_gr_sha256() {
  { sha256sum "$1" 2>/dev/null || shasum -a 256 "$1" 2>/dev/null; } | awk '{print $1; exit}'
}

_gr_reg_fail() { echo "[FAIL] $1. Nothing was registered." >&2; }

# soif_cdf_register_hooks ROOT CLONE [check] — `## BL-320:` (c2), the part of
# `## BL-319:` approval design B cannot work without: a Guardrails release that
# adds a hook (4.4.0's record-approval.sh) reaches an existing project's files
# through the refresh, but runs only once .claude/settings.json registers it.
#
# The entries are CDF's own: the clone's scripts/_shared.sh
# generate_settings_json — what its sync.sh feeds merge_hooks_into_settings —
# run on the manifest's activeHooks, never a hand-kept copy. An entry is added
# when its hook file is in ROOT/.claude/framework/hooks/ and no entry of the
# same event already runs that file (any spelling of the command, any matcher).
# Each addition is APPENDED to its event's list as its own group, as the
# generator emitted it — type, command and (`## BL-375:`, Guardrails 4.5.0)
# the failure policy, timeout and onFailure, with any key a later release
# adds. No existing entry — the Guardrails', Solo's or the user's — is removed
# or reordered; a Guardrails entry already registered has its own timeout and
# onFailure REFRESHED in place when they differ from the generated entry's
# (absent counts as different), and nothing else on it is touched. CDF's own
# merge cannot be reused: it replaces the whole `hooks` key, which drops
# Solo's hooks and the user's. Removing entries for hooks a release dropped,
# and the deny rules, stay `## BL-319:`'s.
#
# The generator's stderr is kept (`## BL-375:`): each line is shown as
# "Guardrails generator: …" — 4.5.0's WARNING that the policy was not written,
# its ERROR of a refusal — and a non-zero return refuses with that message.
#
# Prints each addition as "  + EVENT[ (MATCHER)]: COMMAND" and each refresh as
# "  ~ EVENT[ (MATCHER)]: COMMAND timeout=… onFailure=…" (the entry as the
# file spells it), or that none is missing; `check` prints the hook names that
# would be added, then "NAME timeout=… onFailure=…" for each that would be
# refreshed, and writes nothing. Refuses loudly, writing nothing, on a
# symlinked settings.json, one that is not a JSON object of lists, a missing
# manifest, a clone with no generator, or a generator that returned non-zero.
# Atomic: a temp file beside settings.json, renamed over it.
soif_cdf_register_hooks() {
  local root="$1" clone="$2" mode="${3:-apply}"
  local st="$root/.claude/settings.json" mf="$root/.claude/manifest.json" shared="$clone/scripts/_shared.sh"
  local gen="" gen_rc=0 gen_err="" errf="" line="" ev="" cmd="" name="" have=0 missing="" refresh="" n=0 nr=0
  local add="{}" ref="[]" plan="[]" prog="" tmp="" perm="" lost="" rlost=""
  local -a active=()
  [ ! -L "$st" ] || { _gr_reg_fail ".claude/settings.json is a symlink, so registering would write through it to wherever it points"; return 1; }   # BL-320-REG-LINK
  [ -f "$st" ] || { _gr_reg_fail "there is no .claude/settings.json to register the Guardrails hooks in"; return 1; }
  jq -e 'type == "object" and ((.hooks // {}) | type) == "object" and all((.hooks // {})[]; type == "array")' "$st" >/dev/null 2>&1 || { _gr_reg_fail ".claude/settings.json is not a JSON object whose hooks are lists"; return 1; }   # BL-320-REG-JSON
  [ -f "$mf" ] || { _gr_reg_fail "there is no .claude/manifest.json, so which Guardrails hooks are active is unknown"; return 1; }
  while IFS= read -r name; do
    [ -n "$name" ] && active+=("$name")
  done < <(jq -r '(.activeHooks // [])[]? | strings' "$mf" 2>/dev/null)
  if [ "${#active[@]}" -eq 0 ]; then
    [ "$mode" = check ] || echo "Guardrails hook registrations: none missing (.claude/manifest.json lists no active hooks)"
    return 0
  fi
  [ -f "$shared" ] || { _gr_reg_fail "the Guardrails clone at $clone has no scripts/_shared.sh, so its hook entries cannot be read"; return 1; }
  # `## BL-375:` the generator's stderr is kept — 4.5.0's WARNING that the
  # policy was not written, its ERROR of a refusal — and shown with its
  # origin; its return code decides, so a refusal never reads as nothing to
  # register.
  errf="$(mktemp "${TMPDIR:-/tmp}/soif-gr-gen.XXXXXX")" || { _gr_reg_fail "could not create a temporary file for the Guardrails generator's messages"; return 1; }
  gen="$( ( . "$shared" >/dev/null 2>&1; command -v generate_settings_json >/dev/null 2>&1 || exit 3
            generate_settings_json "${active[@]}" ) 2>"$errf" )" || gen_rc=$?   # BL-375-GEN-STDERR
  gen_err="$(LC_ALL=C tr -d '\000' < "$errf" 2>/dev/null || :)"; rm -f "$errf"
  [ -z "$gen_err" ] || printf '%s\n' "$gen_err" | sed 's/^/Guardrails generator: /' >&2   # BL-375-GEN-SHOW
  if [ "$gen_rc" -ne 0 ]; then   # BL-375-GEN-RC
    [ "$gen_rc" -ne 3 ] || { _gr_reg_fail "the Guardrails clone at $clone has no generate_settings_json in scripts/_shared.sh, so its hook entries cannot be read"; return 1; }
    gen_err="$(printf '%s' "$gen_err" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    _gr_reg_fail "the Guardrails clone at $clone refused to generate its hook entries (scripts/_shared.sh generate_settings_json returned $gen_rc)${gen_err:+: ${gen_err%.}}"; return 1
  fi
  jq -e '(.hooks | type) == "object"' <<< "$gen" >/dev/null 2>&1 \
    || { _gr_reg_fail "the Guardrails clone at $clone could not generate its hook entries (scripts/_shared.sh generate_settings_json printed no hooks object)"; return 1; }
  # Each generated entry travels whole ({event, matcher, entry}); the entry is
  # what the generator emitted, never rebuilt (the ENTRY-WHOLE line below).
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    ev="$(jq -r .event <<< "$line")"; cmd="$(jq -r '.entry.command // "" | tostring' <<< "$line")"
    case "$cmd" in *.claude/framework/hooks/*.sh) ;; *) continue ;; esac
    name="${cmd##*/}"
    [ -f "$root/.claude/framework/hooks/$name" ] || continue   # BL-320-REG-FILE
    have=0
    jq -e --arg e "$ev" --arg n ".claude/framework/hooks/$name" 'any((.hooks[$e] // [])[]?.hooks[]?; (.command // "") | tostring | contains($n))' "$st" >/dev/null 2>&1 && have=1   # BL-320-REG-HAVE
    if [ "$have" = 1 ]; then
      # `## BL-375:` registered already: refreshed when any entry of that
      # event running this file differs in a timeout or onFailure the
      # generated entry CARRIES; a field the generated entry lacks is never a
      # reason (review round 3: under a Claude Code older than 2.1.295 the
      # generator emits no onFailure, and a registered "block" must stay).
      jq -e --arg e "$ev" --arg n ".claude/framework/hooks/$name" --argjson g "$(jq -c .entry <<< "$line")" 'any((.hooks[$e] // [])[]?.hooks[]?; ((.command // "") | tostring | contains($n)) and ((($g | has("timeout")) and (.timeout != $g.timeout)) or (($g | has("onFailure")) and (.onFailure != $g.onFailure))))' "$st" >/dev/null 2>&1 || continue   # BL-375-POLICY-DIFF
      case "$refresh" in *"$line"*) continue ;; esac
      refresh="$refresh$line"$'\n'
      nr=$((nr + 1))
      continue
    fi
    case "$missing" in *"$line"*) continue ;; esac
    missing="$missing$line"$'\n'
    n=$((n + 1))
  done < <(jq -c '.hooks | to_entries[] | .key as $e | .value[]? | (.matcher // "") as $m | .hooks[]? | select(type == "object") | {event: $e, matcher: $m, entry: .}' <<< "$gen")   # BL-375-ENTRY-WHOLE
  if [ "$n" -eq 0 ] && [ "$nr" -eq 0 ]; then
    [ "$mode" = check ] || echo "Guardrails hook registrations: none missing from .claude/settings.json, none to refresh"
    return 0
  fi
  # `## BL-375:` the refresh plan, read from the file BEFORE the write: every
  # registered entry a refresh touches, as the file spells it, with its timeout
  # and onFailure before (bt, bo) and after (at, ao) — a field the generated
  # entry lacks keeps the registered value and is listed under "kept". Check
  # mode and the report after the write print from it.
  [ "$nr" -eq 0 ] || plan="$(printf '%s' "$refresh" | jq -sc --slurpfile s "$st" 'def fv: if . == null then "none" else tostring end;
      [ .[] as $e | ($e.entry.command | split("/") | last) as $n
        | ($s[0].hooks[$e.event] // [])[]? | (.matcher // "") as $m | .hooks[]?
        | select((.command // "") | tostring | contains(".claude/framework/hooks/" + $n))
        | {event: $e.event, matcher: $m, command: .command, name: ($n | sub("\\.sh$"; "")), bt: .timeout, bo: .onFailure,
           at: (if ($e.entry | has("timeout")) then $e.entry.timeout else .timeout end),
           ao: (if ($e.entry | has("onFailure")) then $e.entry.onFailure else .onFailure end),
           kept: [ (if (($e.entry | has("timeout")) | not) and (.timeout != null) then "timeout=" + (.timeout | fv) else empty end),
                   (if (($e.entry | has("onFailure")) | not) and (.onFailure != null) then "onFailure=" + (.onFailure | fv) else empty end) ]} ]')" \
    || { _gr_reg_fail "could not read the entries to refresh"; return 1; }
  if [ "$mode" = check ]; then
    [ "$n" -eq 0 ] || printf '%s' "$missing" | jq -r '.entry.command | split("/") | last | sub("\\.sh$"; "")'
    [ "$nr" -eq 0 ] || jq -r 'def fv: if . == null then "none" else tostring end; [.[] | "\(.name) timeout=\(.at | fv) onFailure=\(.ao | fv)"] | unique[]' <<< "$plan"   # BL-375-CHECK-REFRESH
    return 0
  fi
  [ "$n" -eq 0 ] || add="$(printf '%s' "$missing" | jq -s 'group_by(.event) | map({key: .[0].event,
           value: (group_by(.matcher) | map((if .[0].matcher != "" then {matcher: .[0].matcher} else {} end) + {hooks: map(.entry)}))})
         | from_entries')" || { _gr_reg_fail "could not build the entries to add"; return 1; }
  [ "$nr" -eq 0 ] || ref="$(printf '%s' "$refresh" | jq -sc 'map({event: .event, name: (".claude/framework/hooks/" + (.entry.command | split("/") | last)), entry: .entry})')" || { _gr_reg_fail "could not build the entries to refresh"; return 1; }
  prog='.hooks = (reduce ($add | to_entries[]) as $e ((.hooks // {}); .[$e.key] = ((.[$e.key] // []) + $e.value)))'   # BL-320-REG-APPEND
  # `## BL-375:` then, on every entry of the event that runs the refreshed
  # hook's file (any spelling, any matcher): its timeout and onFailure become
  # the generated entry's where the generated entry carries them; a field it
  # lacks is KEPT — the refresh adds or strengthens a policy, never loosens one
  # (review round 3) — and nothing else on the entry, in its group or in its
  # event is touched.
  prog="$prog"' | reduce $ref[] as $r (.; .hooks[$r.event] |= map(if (.hooks | type) == "array" then .hooks |= map(if ((.command // "") | tostring | contains($r.name)) then (if ($r.entry | has("timeout")) then .timeout = $r.entry.timeout else . end | if ($r.entry | has("onFailure")) then .onFailure = $r.entry.onFailure else . end) else . end) else . end))'   # BL-375-POLICY-REFRESH
  tmp="$(mktemp "$st.XXXXXX")" || { _gr_reg_fail "could not create a temporary file beside .claude/settings.json"; return 1; }
  perm="$(stat -c '%a' "$st" 2>/dev/null || stat -f '%Lp' "$st" 2>/dev/null || echo 644)"
  if jq --argjson add "$add" --argjson ref "$ref" "$prog" "$st" > "$tmp" 2>/dev/null && chmod "$perm" "$tmp" && mv -f "$tmp" "$st"; then
    # The receipt (review round 1, R-7a): re-read the file and find every
    # entry in it, rather than reporting the list this function computed.
    lost="$(printf '%s' "$missing" | jq -r --slurpfile s "$st" 'select(. as $e | ($s[0].hooks[$e.event] // []) | any(.[]?.hooks[]?; .command == $e.entry.command) | not) | .entry.command' 2>/dev/null)" \
      || lost="(.claude/settings.json could not be read back)"
    # `## BL-375:` and every refreshed entry now carries the generated policy.
    rlost="$(printf '%s' "$refresh" | jq -r --slurpfile s "$st" 'select(. as $e | ($s[0].hooks[$e.event] // []) | any(.[]?.hooks[]?; ((.command // "") | tostring | contains(".claude/framework/hooks/" + ($e.entry.command | split("/") | last))) and ((($e.entry | has("timeout")) and (.timeout != $e.entry.timeout)) or (($e.entry | has("onFailure")) and (.onFailure != $e.entry.onFailure))))) | .entry.command' 2>/dev/null)" || rlost="(.claude/settings.json could not be read back)"   # BL-375-REFRESH-RECEIPT
    [ -z "$rlost" ] || lost="${lost:+$lost }$rlost"
    [ -z "$lost" ] || { [ ! -f "$tmp" ] || rm -f "$tmp"; _gr_reg_fail "the registrations did not land in .claude/settings.json: $(printf '%s' "$lost" | tr '\n' ' ')"; return 1; }   # BL-320-REG-RECEIPT
    if [ "$n" -gt 0 ] && [ "$nr" -gt 0 ]; then echo "Guardrails hook registrations added to and refreshed in .claude/settings.json (nothing else in it changed):"
    elif [ "$n" -gt 0 ]; then echo "Guardrails hook registrations added to .claude/settings.json (nothing else in it changed):"
    else echo "Guardrails hook registrations refreshed in .claude/settings.json (nothing else in it changed):"; fi
    [ "$n" -eq 0 ] || printf '%s' "$missing" | jq -r '"  + \(.event)\(if .matcher != "" then " (" + .matcher + ")" else "" end): \(.entry.command)"'
    [ "$nr" -eq 0 ] || jq -r 'def fv: if . == null then "none" else tostring end; def ch(b; a): if b == a then (a | fv) else (b | fv) + "->" + (a | fv) end;
        .[] | "  ~ \(.event)\(if .matcher != "" then " (" + .matcher + ")" else "" end): \(.command) timeout=\(ch(.bt; .at)) onFailure=\(ch(.bo; .ao))\(if (.kept | length) > 0 then " (kept " + (.kept | join(", ")) + ": the generator emitted none)" else "" end)"' <<< "$plan"
    return 0
  fi
  rm -f "$tmp"
  _gr_reg_fail "could not write .claude/settings.json"
  return 1
}

# soif_guardrails_clone_update CLONE NONINTERACTIVE — `## BL-320:` (Karl,
# 2026-10-06): init.sh no longer pulls the shared clone on its own. At a
# terminal it shows the clone's version (and, when a fetch needs no prompt,
# the version available) and asks; Enter is yes. With no one to ask — no TTY,
# CI, SOIF_NONINTERACTIVE, or --non-interactive — it never pulls or fetches; it
# prints the command. Either way a clone below the minimum is named.
soif_guardrails_clone_update() {
  local clone="$1" ni="${2:-false}" cur avail="" head
  cur="$(tr -d '[:space:]' < "$clone/FRAMEWORK_VERSION" 2>/dev/null || :)"
  head="$(git -C "$clone" rev-parse --short HEAD 2>/dev/null || :)"
  if [ "$ni" = true ] || [ ! -t 0 ] || [ -n "${CI:-}" ] || [ -n "${SOIF_NONINTERACTIVE:-}" ]; then   # BL-320-PULL-TTY
    print_info "Development Guardrails clone at $clone: ${cur:-version unknown}${head:+ ($head)}. Not updated: this run cannot ask first."
    print_info "To update it (every project on this computer uses it): git -C \"$clone\" pull --ff-only"
  else
    if soif_gr_git_noprompt -C "$clone" fetch --quiet >/dev/null 2>&1; then
      avail="$(git -C "$clone" show '@{upstream}:FRAMEWORK_VERSION' 2>/dev/null | tr -d '[:space:]' || :)"
    fi
    print_info "Development Guardrails clone at $clone: ${cur:-version unknown}${head:+ ($head)} installed${avail:+, $avail available}."
    if prompt_yes_no "Update the shared clone now? Every project on this computer uses it [Y/n]" "Y"; then   # BL-320-PULL-ASK
      if soif_gr_git_noprompt -C "$clone" pull --ff-only --quiet >/dev/null 2>&1; then
        cur="$(tr -d '[:space:]' < "$clone/FRAMEWORK_VERSION" 2>/dev/null || :)"
        print_ok "Development Guardrails clone updated: ${cur:-version unknown}"
      else
        print_warn "Could not update the clone (offline, or it has local changes) — using ${cur:-it as it is}"
      fi
    else
      print_info "Kept the clone at ${cur:-its current version}."
    fi
  fi
  soif_gr_below_min "$cur" && print_warn "The Development Guardrails clone is $cur, older than $SOIF_GUARDRAILS_MIN, the minimum for this framework's fail-closed hook policy and runaway scan. Until it is updated a guard that hangs, crashes or cannot start lets the action it guards through, and every Claude Code session start offers the update."   # BL-320-PULL-MIN
  return 0
}

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
#   SOIF_GUARDRAILS_MIN            the minimum Guardrails version for this
#                                  framework's approval questions — the ONE
#                                  place the number is written
#   soif_gr_route ROOT             pick | legacy | unknown — how a question in
#                                  ROOT is answered, from its manifest
#   soif_pa_v2_problems FILE       CDF's rules for a schema-2 question
#   soif_pa_option_lines FILE      each option and its effect, either schema
#   soif_cdf_register_hooks ROOT CLONE [check]
#                                  the Guardrails hook entries ROOT's manifest
#                                  activates but .claude/settings.json lacks
#                                  (Karl's c2, 2026-10-06): added, never
#                                  removed, reordered or rewritten
#   soif_guardrails_clone_update CLONE NONINTERACTIVE
#                                  init.sh's ask-first update of the shared
#                                  clone (needs helpers-core.sh's print_* and
#                                  prompt_yes_no)
#
# Shipped to every project (init.sh `# BL-320-SHIP`). bash 3.2 safe; needs jq.
# shellcheck shell=bash

SOIF_GUARDRAILS_MIN="4.4.0"

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

# soif_gr_below_min V — true when V is a version and is older than the minimum.
soif_gr_below_min() {
  soif_gr_xyz_valid "${1:-}" && [ "$(soif_gr_xyz_cmp "$1" "$SOIF_GUARDRAILS_MIN")" = lt ]
}

# soif_gr_installed_version ROOT — ROOT's .claude/manifest.json frameworkVersion.
soif_gr_installed_version() {
  jq -r '(.frameworkVersion // empty) | tostring' "$1/.claude/manifest.json" 2>/dev/null || :
}

# soif_gr_route ROOT — how a question in ROOT is answered:
#   pick    Guardrails at or above the minimum: the user replies with the
#           option id, twice, and the Guardrails record the pick
#   legacy  an older version: the user answers in words; the agent clears the
#           question and records the approval itself
#   unknown no readable version (no manifest, no Guardrails, a stub)
soif_gr_route() {
  local v c
  v="$(soif_gr_installed_version "${1:-.}")"
  soif_gr_xyz_valid "$v" || { echo unknown; return 0; }
  c="$(soif_gr_xyz_cmp "$v" "$SOIF_GUARDRAILS_MIN")"
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
# above the minimum) in ROOT would leave a writer they cannot take an answer
# from: the mixed install `## BL-320:` exists to prevent. Both halves must move
# together, by the framework sync.
soif_gr_mixed() {
  local w=""
  soif_gr_xyz_valid "${2:-}" && ! soif_gr_below_min "$2" || return 1
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
# Each addition is APPENDED to its event's list as its own group; no existing
# entry — the Guardrails', Solo's or the user's — is removed, reordered or
# rewritten. CDF's own merge cannot be reused: it replaces the whole `hooks`
# key, which drops Solo's hooks and the user's. Removing entries for hooks a
# release dropped, and the deny rules, stay `## BL-319:`'s.
#
# Prints each addition as "  + EVENT[ (MATCHER)]: COMMAND", or that none is
# missing; `check` prints the hook names that would be added and writes
# nothing. Refuses loudly, writing nothing, on a symlinked settings.json, one
# that is not a JSON object of lists, a missing manifest, or a clone with no
# generator. Atomic: a temp file beside settings.json, renamed over it.
soif_cdf_register_hooks() {
  local root="$1" clone="$2" mode="${3:-apply}"
  local st="$root/.claude/settings.json" mf="$root/.claude/manifest.json" shared="$clone/scripts/_shared.sh"
  local gen entry ev m cmd name missing="" add prog tmp perm lost="" n=0
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
  gen="$( ( . "$shared" >/dev/null 2>&1; command -v generate_settings_json >/dev/null 2>&1 || exit 3
            generate_settings_json "${active[@]}" ) 2>/dev/null )" \
    && jq -e '(.hooks | type) == "object"' <<< "$gen" >/dev/null 2>&1 \
    || { _gr_reg_fail "the Guardrails clone at $clone could not generate its hook entries (scripts/_shared.sh generate_settings_json)"; return 1; }
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    ev="$(jq -r .event <<< "$entry")"; m="$(jq -r .matcher <<< "$entry")"; cmd="$(jq -r .command <<< "$entry")"
    case "$cmd" in *.claude/framework/hooks/*.sh) ;; *) continue ;; esac
    name="${cmd##*/}"
    [ -f "$root/.claude/framework/hooks/$name" ] || continue   # BL-320-REG-FILE
    jq -e --arg e "$ev" --arg n ".claude/framework/hooks/$name" 'any((.hooks[$e] // [])[]?.hooks[]?; (.command // "") | tostring | contains($n))' "$st" >/dev/null 2>&1 && continue   # BL-320-REG-HAVE
    case "$missing" in *"$entry"*) continue ;; esac
    missing="$missing$entry"$'\n'
    n=$((n + 1))
  done < <(jq -c '.hooks | to_entries[] | .key as $e | .value[]? | (.matcher // "") as $m | .hooks[]? | {event: $e, matcher: $m, command: .command}' <<< "$gen")
  if [ "$n" -eq 0 ]; then
    [ "$mode" = check ] || echo "Guardrails hook registrations: none missing from .claude/settings.json"
    return 0
  fi
  if [ "$mode" = check ]; then
    printf '%s' "$missing" | jq -r '.command | split("/") | last | sub("\\.sh$"; "")'
    return 0
  fi
  add="$(printf '%s' "$missing" | jq -s 'group_by(.event) | map({key: .[0].event,
           value: (group_by(.matcher) | map((if .[0].matcher != "" then {matcher: .[0].matcher} else {} end) + {hooks: map({type: "command", command: .command})}))})
         | from_entries')" || { _gr_reg_fail "could not build the entries to add"; return 1; }
  prog='.hooks = (reduce ($add | to_entries[]) as $e ((.hooks // {}); .[$e.key] = ((.[$e.key] // []) + $e.value)))'   # BL-320-REG-APPEND
  tmp="$(mktemp "$st.XXXXXX")" || { _gr_reg_fail "could not create a temporary file beside .claude/settings.json"; return 1; }
  perm="$(stat -c '%a' "$st" 2>/dev/null || stat -f '%Lp' "$st" 2>/dev/null || echo 644)"
  if jq --argjson add "$add" "$prog" "$st" > "$tmp" 2>/dev/null && chmod "$perm" "$tmp" && mv -f "$tmp" "$st"; then
    # The receipt (review round 1, R-7a): re-read the file and find every
    # entry in it, rather than reporting the list this function computed.
    lost="$(printf '%s' "$missing" | jq -r --slurpfile s "$st" 'select(. as $e | ($s[0].hooks[$e.event] // []) | any(.[]?.hooks[]?; .command == $e.command) | not) | .command' 2>/dev/null)" \
      || lost="(.claude/settings.json could not be read back)"
    [ -z "$lost" ] || { [ ! -f "$tmp" ] || rm -f "$tmp"; _gr_reg_fail "the registrations did not land in .claude/settings.json: $(printf '%s' "$lost" | tr '\n' ' ')"; return 1; }   # BL-320-REG-RECEIPT
    echo "Guardrails hook registrations added to .claude/settings.json (nothing else in it changed):"
    printf '%s' "$missing" | jq -r '"  + \(.event)\(if .matcher != "" then " (" + .matcher + ")" else "" end): \(.command)"'
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
  soif_gr_below_min "$cur" && print_warn "The Development Guardrails clone is $cur, older than $SOIF_GUARDRAILS_MIN, the minimum for this framework's approval questions. Until it is updated the agent approves its own commits the older way, and every Claude Code session start offers the update."   # BL-320-PULL-MIN
  return 0
}

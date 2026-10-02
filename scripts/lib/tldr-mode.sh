#!/usr/bin/env bash
# scripts/lib/tldr-mode.sh — `## BL-312:` TL;DR mode, the pieces every writer
# of the choice shares: the question, the [y/N] reader, the CLAUDE.md section,
# and the Stop-hook registration.
#
# THE CHOICE LIVES IN ONE PLACE: `tldr_mode` in `.claude/manifest.json`. `true`
# is on; `false`, an absent key, or a manifest that cannot be read is off (the
# hook, scripts/hooks/tldr-check.sh, says why off is the right reading there).
# Its writers: init.sh (the interactive question, or `tldr_mode` in --config),
# adoption (its last question) and `scripts/reconfigure-project.sh --tldr-mode`.
# An upgrade keeps it — every manifest write there merges.
#
# THE HOOK ENFORCES PRESENCE; CLAUDE.md STATES THE CONTENT. The section below is
# written into a project's CLAUDE.md only while the mode is on, between two
# marker lines, so it can be taken out again byte for byte.
#
# Sourced from the framework clone by init.sh and scripts/lib/claude-settings.sh,
# and from a project's own scripts/lib/ by reconfigure-project.sh — so init.sh
# ships it. Pure functions; bash 3.2; safe under `set -euo pipefail`.

SOIF_TLDR_QUESTION="Do you want every reply to end with a plain-English summary of what happened, your options and a recommendation?"
SOIF_TLDR_BEGIN='<!-- tldr-mode:begin -->'
SOIF_TLDR_END='<!-- tldr-mode:end -->'
# The same spelling as every other hook in the roster (scripts/lib/claude-settings.sh).
SOIF_TLDR_HOOK_CMD='bash "$CLAUDE_PROJECT_DIR"/scripts/hooks/tldr-check.sh'

# soif_tldr_yes ANSWER — 0 iff ANSWER is a yes to a `[y/N]` question: it starts
# with y or Y, the reading init.sh gives its other [y/N] prompts. Anything else,
# nothing included, is no.
soif_tldr_yes() {
  case "${1:-}" in [Yy]*) return 0 ;; esac   # BL-312-TLDR-YES
  return 1
}

# soif_tldr_claude_md_section — the CLAUDE.md section, markers included, with no
# trailing blank line. Short on purpose: the generated CLAUDE.md is already long.
soif_tldr_claude_md_section() {
  printf '%s\n' "$SOIF_TLDR_BEGIN"
  cat <<'TLDRSECTION'
### TL;DR Mode (on)
The person you work for chose this (`tldr_mode: true` in `.claude/manifest.json`). End **every**
reply — status lines and short answers included — with exactly one section headed **TL;DR**, in
plain English for someone who is not a programmer, restated in full every time (never "as above"),
carrying these eight parts in order:
1. what happened; 2. what it means for them; 3. next steps; 4. what is waiting on them;
5. the options; 6. the pros and cons of each option; 7. your recommendation, with its reasoning;
8. what happens if they do nothing.
Every command they must run goes in a fenced code block, never named only in prose. Keep the words
"terminal" and "shell" out of any sentence that also says "run", "do" or "execute" — "if they do
nothing" included: the bypass detector reads that as a proposed workaround. The TL;DR is additive:
the technical account above it stays in full, and `docs/reference/messaging-standard.md` still
governs its words. A Stop hook (`scripts/hooks/tldr-check.sh`) sends a reply back, once a turn, when
it has no TL;DR outside a code block. To turn it off: `bash scripts/reconfigure-project.sh --tldr-mode off`.
TLDRSECTION
  printf '%s\n' "$SOIF_TLDR_END"
}

# soif_tldr_claude_md_state FILE — prints `absent`, `present` (one well-formed
# section) or `damaged` (an opener without a closer, a closer first, or more
# than one section). rc 1 when FILE cannot be read.
soif_tldr_claude_md_state() {
  [ -f "$1" ] && [ -r "$1" ] || return 1
  awk -v b="$SOIF_TLDR_BEGIN" -v e="$SOIF_TLDR_END" '
    BEGIN { nb = 0; open = 0; bad = 0 }
    $0 == b { nb++; if (open) bad = 1; open = 1; next }
    $0 == e { if (!open) bad = 1; open = 0; next }
    END {
      if (open || bad || nb > 1) print "damaged"
      else if (nb == 1) print "present"
      else print "absent"
    }' "$1"
}

# soif_tldr_apply_claude_md FILE on|off — put the section in (at the end) or take
# it out, so that FILE says what the manifest says. Idempotent: `on` twice
# changes nothing the second time, and `off` after `on` gives back the exact
# bytes that were there before — the one blank line `on` adds goes with it.
# rc 0 done (changed or not); 1 bad arguments or FILE unreadable/unwritable;
# 2 the markers are damaged, and FILE is left exactly as it was.
soif_tldr_apply_claude_md() {
  local f="$1" want="${2:-}" state="" tmp=""
  case "$want" in on|off) : ;; *) return 1 ;; esac
  state="$(soif_tldr_claude_md_state "$f")" || return 1
  [ "$state" = "damaged" ] && return 2   # BL-312-TLDR-DAMAGED
  tmp="$f.tldr-mode.$$"
  if [ "$state" = "present" ]; then
    # Drop the section and the ONE blank line straight above it. Blank lines are
    # held back one at a time and only printed once a non-section line follows.
    awk -v b="$SOIF_TLDR_BEGIN" -v e="$SOIF_TLDR_END" '
      $0 == b { skip = 1; held = 0; next }   # BL-312-TLDR-HELD-BLANK
      skip { if ($0 == e) skip = 0; next }
      { if (held) { print ""; held = 0 }
        if ($0 == "") { held = 1; next }
        print }
      END { if (held) print "" }' "$f" > "$tmp" || { rm -f "$tmp"; return 1; }
  else
    cat "$f" > "$tmp" || { rm -f "$tmp"; return 1; }
  fi
  if [ "$want" = "on" ]; then
    # A file that does not end in a newline gets one first, so the section
    # starts on a line of its own.
    if [ -s "$tmp" ] && [ -n "$(tail -c 1 "$tmp")" ]; then printf '\n' >> "$tmp"; fi
    { printf '\n'; soif_tldr_claude_md_section; } >> "$tmp" || { rm -f "$tmp"; return 1; }
  fi
  if cmp -s "$tmp" "$f"; then rm -f "$tmp"; return 0; fi
  cat "$tmp" > "$f" || { rm -f "$tmp"; return 1; }
  rm -f "$tmp"
  return 0
}

# soif_tldr_register_hook SETTINGS_FILE — register the TL;DR Stop hook in the
# first Stop group, the group the framework's other Stop hooks use (the bypass
# detector, the Qdrant reminder), and the Development Guardrails' stop-checklist
# when they are installed. Idempotent. rc 0 added; 1 already there; 2 the edit
# failed (SETTINGS_FILE is left as it was).
soif_tldr_register_hook() {
  local _f="$1"
  if jq -e '[.hooks.Stop[]?.hooks[]?.command | strings] | any(contains("scripts/hooks/tldr-check.sh"))' "$_f" >/dev/null 2>&1; then
    return 1
  fi
  if jq --arg c "$SOIF_TLDR_HOOK_CMD" \
       'if (.hooks.Stop // []) | length == 0
        then .hooks.Stop = [{"hooks":[{"type":"command","command":$c}]}]
        else .hooks.Stop[0].hooks += [{"type":"command","command":$c}]
        end' "$_f" > "$_f.tmp" 2>/dev/null && mv "$_f.tmp" "$_f"; then
    return 0
  fi
  rm -f "$_f.tmp"
  return 2
}

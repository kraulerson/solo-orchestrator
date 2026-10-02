#!/usr/bin/env bash
# scripts/hooks/tldr-check.sh — `## BL-312:` the TL;DR-mode Stop hook.
#
# When the person this project's agent works for chose TL;DR mode (`tldr_mode:
# true` in .claude/manifest.json), every reply must end with one plain-English
# TL;DR. This hook checks the one thing a script can check honestly — that a
# TL;DR line exists OUTSIDE code fences — and when there is none it sends the
# reply back with the eight parts and the command rule spelled out. The
# project's CLAUDE.md ("TL;DR Mode") states the content; this enforces presence.
#
# NO PER-PART PARSING. Whether a sentence says "what it means for them" is a
# judgment, and a hook that judged it would send back replies it cannot read.
# It reads ONLY `last_assistant_message`, never the transcript.
#
# IT CANNOT LOOP. Claude Code sets `stop_hook_active` on the stop that follows a
# block; this exits 0 on it at once, so a reply goes back at most once a turn,
# whatever the second reply says.
#
# IT FAILS OPEN, ON PURPOSE — and under docs/messaging-standard.md a check that
# fails open by design is itself the finding, so here it is: no jq, no manifest,
# a manifest that is not a JSON object, or a `tldr_mode` that is absent or not
# exactly `true` all read as OFF. TL;DR mode is a reply-format preference the
# person opted into, not a safety check: nothing is left unprotected when it is
# skipped, and a format check that sent back every reply in a project whose
# manifest it could not read would be noise. The one case that would be silent
# is said: a missing jq prints one line to stderr.
#
# Mirrors the TL;DR arm of the reference Stop check in Karl's own workflow
# (stop-checks.sh + _stopcheck.awk): the same fence rule, the same token. Wired
# in the first Stop group by scripts/lib/claude-settings.sh beside the bypass
# detector; both exit at once on `stop_hook_active`.
#
# bash 3.2. Input: the Stop hook's JSON envelope on stdin. Always exits 0.
set -u

if ! command -v jq >/dev/null 2>&1; then
  echo "tldr-check: jq is not installed, so TL;DR mode was not checked (scripts/hooks/tldr-check.sh)." >&2   # BL-312-TLDR-NOJQ
  exit 0
fi

input="$(cat)"
active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)"
[ "$active" = "true" ] && exit 0   # BL-312-TLDR-ONCE

# The project: Claude Code's CLAUDE_PROJECT_DIR, else the project this file sits
# in (<project>/scripts/hooks/).
root="${CLAUDE_PROJECT_DIR:-}"
[ -n "$root" ] || root="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)"   # BL-312-TLDR-ROOT
mode="$(jq -r 'if type == "object" then (.tldr_mode == true) else false end' "$root/.claude/manifest.json" 2>/dev/null)"
[ "$mode" = "true" ] || exit 0   # BL-312-TLDR-OFF

text="$(printf '%s' "$input" | jq -r '.last_assistant_message // empty' 2>/dev/null)"
[ -n "$text" ] || exit 0

# A TL;DR line: the token tl;dr or tldr standing alone (not part of a filename
# or an identifier), on a line outside every ``` or ~~~ fence.
if printf '%s\n' "$text" | awk '
  BEGIN {
    fence = 0; found = 0
    tlre = "(^|[^a-z0-9_/.-])tl;?dr([^a-z0-9_.-]|$)"   # BL-312-TLDR-TOKEN
  }
  { l = tolower($0) }
  l ~ /^[[:space:]]*(```|~~~)/ { fence = !fence; next }   # BL-312-TLDR-FENCE
  !fence && l ~ tlre { found = 1 }
  END { exit found ? 0 : 1 }'; then
  exit 0
fi

reason="TL;DR mode is on for this project (tldr_mode is true in .claude/manifest.json), and this reply has no TL;DR outside a code block. Add it now, as the end of this reply; the technical account you already wrote stands. Head it TL;DR and write it in plain English for someone who is not a programmer, restated in full every time, never \"as above\". It carries eight parts: (1) what happened; (2) what it means for them; (3) next steps; (4) what is waiting on them; (5) the options; (6) the pros and cons of each option; (7) your recommendation, with its reasoning; (8) what happens if they do nothing. Put every command they must run in a fenced code block, never named only in prose."
jq -n --arg r "$reason" '{decision: "block", reason: $r}'   # BL-312-TLDR-BLOCK
exit 0

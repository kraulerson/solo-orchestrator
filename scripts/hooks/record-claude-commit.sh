#!/usr/bin/env bash
# scripts/hooks/record-claude-commit.sh — BL-030 PostToolUse hook.
#
# Records the SHA of every successful git commit issued by Claude into
# .claude/claude-commits.jsonl. Always-on, regardless of enforcement_level.
# The ledger is the substrate the out-of-band detector uses to distinguish
# Claude-issued commits from user-terminal commits.
#
# Stdin: JSON envelope from Claude Code's PostToolUse hook contract. For the
# Bash tool:
#   { "hook_event_name": "PostToolUse", "tool_input": {"command": "..."},
#     "tool_response": { "stdout", "stderr", "interrupted", "isImage",
#                        "noOutputExpected",
#                        "gitOperation": {"commit": {"sha", "kind", "branch"}} } }
#
# `## BL-324:` WHAT SAYS A COMMIT WAS MADE, AND WHICH ONE. This hook used to
# read tool_response.exit_code and treat its absence as a failure. Claude Code
# sends no exit code for Bash, so it never wrote a row, and the out-of-band
# detector labelled every agent commit a terminal commit. PostToolUse fires only
# for a call that succeeded (a failed one fires PostToolUseFailure, measured for
# `## BL-233:`), but a call can succeed while the commit in it failed
# (`git commit -m x; true`, or `|| true`), and then HEAD is a commit the call did
# not make: possibly the user's own, which recording would hide from the
# detector. So the commit recorded is the one the host names:
# tool_response.gitOperation.commit.sha, which Claude Code sets when git printed
# the summary line of a commit it made ("[main 1a2b3c4] subject"), checked to be
# a commit object in this repository and recorded by its full SHA.
#
# A `-q` commit prints no summary line, so the host names nothing (251 of the
# 382 agent commits measured for BL-324). For those the commits are proved from
# HEAD's reflog (_reflog_commits): a `commit`, `commit (amend)` or
# `commit (initial)` entry written in the last REFLOG_WINDOW seconds whose
# subject EQUALS the first line of a message that a `git commit` invocation in
# the command supplies itself (-m / --message, or a `-F -` heredoc; _RC_AWK).
# Nothing else in the command counts. A commit that failed writes no entry.
# What that does NOT prove: a commit someone else made in the same window whose
# subject is exactly a message the agent's command supplied (its own commit
# failed, never ran — an uncalled function, `if false`, an unused `||` branch —
# or made the same subject) is taken for the agent's.
#
# No-op conditions:
#   - .claude/ doesn't exist (project not initialized)
#   - the event is not PostToolUse
#   - tool_input.command isn't a `git commit` invocation (`git -C <dir> commit`
#     and `git -c k=v commit` are not, so they are never recorded)
#   - the call was interrupted
#   - tool_response.exit_code is present and not 0 (a host that sends one)
#   - the host names something that is not a commit in this repository
#   - the host names no commit, and HEAD's reflog proves none (above): a message
#     from -F <file>, a pipe (`printf ... | git commit -F -`), $'...', an
#     expansion or an editor; a --dry-run; a commit inside `bash -c` or `eval`;
#     a commit more than REFLOG_WINDOW seconds before the hook runs (or dated
#     back with GIT_COMMITTER_DATE); a commit in another worktree or repository.
#     The detector reports such a commit as out of band, as it reported every
#     commit before BL-324.
#   - jq isn't installed (silent — never block Claude on missing infrastructure)

set -uo pipefail

# Locate project root (CLAUDE_PROJECT_DIR is set by Claude Code; fall back to git).
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "")}"
[ -z "$PROJECT_ROOT" ] && exit 0
[ ! -d "$PROJECT_ROOT/.claude" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Read envelope.
INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
# `## BL-324:` only a call that succeeded; this hook is registered on
# PostToolUse alone, and an envelope that says otherwise is not taken.
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null)
[ "$EVENT" = "PostToolUse" ] || exit 0   # BL-324-EVENT

# Filter: must be a `git commit` (not `git commit-tree`, etc.) and must have succeeded.
#
# Audit finding `specs-plans-bl029-bl030-5` (sibling of BL-020 on the
# pre-commit-gate side): the previous naive substring match
# `case "$CMD" in *"git commit"*)` false-positives on innocuous commands
# whose argv or output happens to contain the literal string `git commit`
# (e.g., `echo "see git commit later"`, `rg "git commit" docs/`,
# `cat scripts/pre-commit-gate.sh | grep "git commit"`). Each false-positive
# polluted the BL-029 ledger with a spurious entry mapped to whatever the
# current HEAD happened to be, which the out-of-band detector then trusted.
#
# Tightened classifier (verbatim from `scripts/pre-commit-gate.sh:81-93`):
#   `commit` must come immediately after `git` (separated only by whitespace),
#   and `git` must NOT be preceded by a quote — so `rg "git commit"` is rejected
#   while `cd /tmp && git commit ...` (preceded by whitespace) is accepted.
#
# --amend semantics (option C from the audit response): no special-casing.
# `git commit --amend` runs the normal flow — the amended commit is recorded
# as a fresh ledger entry under its new HEAD SHA. The pre-amend entry remains
# as an orphan SHA in the append-only ledger; this is acceptable because the
# out-of-band detector matches against ledger membership, so the amended SHA
# is correctly classified as Claude-issued rather than user-terminal. (The host
# names an amended commit with kind "amended" and its new SHA.)
_is_git_commit() {
  echo "$1" | grep -qE '(^|[^"'\''])git[[:space:]]+commit\b'
}
_is_git_commit "$CMD" || exit 0
echo "$CMD" | grep -qE '(^|[^"'\''])git[[:space:]]+commit-tree\b' && exit 0

# `## BL-324:` the success test, and the commit. Anything jq cannot read as
# `false` / `0` is not a success.
INTERRUPTED=$(echo "$INPUT" | jq -r '.tool_response.interrupted // false' 2>/dev/null)
[ "$INTERRUPTED" = "false" ] || exit 0   # BL-324-NOT-INTERRUPTED
EXIT=$(echo "$INPUT" | jq -r '.tool_response.exit_code // 0' 2>/dev/null)
[ "$EXIT" = "0" ] || exit 0   # BL-324-EXIT-CODE

# The window, in seconds, between a commit's reflog entry and this hook. Measured
# over 173 agent commits in Claude Code transcripts (BL-324): the result came
# 2.4 s after the entry at the median, 10.7 s at the 95th percentile, and within
# 30 s for 167 of them; the rest ran a long command after the commit.
REFLOG_WINDOW=30   # BL-324-WINDOW-SECONDS

# `## BL-324:` _RC_AWK reads the command as shell words (single and double
# quotes, backslashes, comments, heredocs; not $'...') and prints, for each
# `git commit` invocation in it, the first line of the message that invocation
# supplies: its -m / --message values (-mX and -m=X attached, as git reads
# them, so -m=X is the message "=X"), or the body of the heredoc on its own
# `-F -` / `--file=-`, including -m "$(cat <<'EOF' ... EOF)". A message with an
# expansion in it ($VAR, $(...), a backquote, an unquoted heredoc that expands)
# is unknown and prints nothing; so does a --dry-run invocation. The line is
# squeezed as git squeezes a reflog message: leading space dropped, runs of
# whitespace made one space, trailing space dropped. Nothing else in the
# command (an echo, a grep pattern, a path, another heredoc) is read.
_RC_AWK='
function addw() {
  if (inw) { cw[c, cn[c]] = cur; cd[c, cn[c]] = dyn; cn[c]++ }
  cur = ""; dyn = 0; inw = 0
}
function endcmd() { addw(); if (cn[c] > 0) { c++; cn[c] = 0 } }
function readline(q,   e) {
  e = index(substr(s, q), "\n")
  if (e == 0) { LINE = substr(s, q); return L + 1 }
  LINE = substr(s, q, e - 1); return q + e
}
function hdword(q,   ch, e) {
  HD = ""; HQ = 0
  while (q <= L) {
    ch = substr(s, q, 1)
    if (ch == "\047" || ch == "\"") {
      e = index(substr(s, q + 1), ch); if (e == 0) return L + 1
      HD = HD substr(s, q + 1, e - 1); HQ = 1; q += e + 1; continue
    }
    if (ch == "\\") { HD = HD substr(s, q + 1, 1); HQ = 1; q += 2; continue }
    if (ch ~ /[ \t\n;&|()<>]/) break
    HD = HD ch; q++
  }
  return q
}
function hdbody(q, d, strip,   first) {
  HB = ""; HOK = 0; first = 1
  while (q <= L) {
    q = readline(q)
    if (strip) sub(/^\t+/, "", LINE)   # BL-324-AWK-TABS
    if (LINE == d) { HOK = 1; return q }
    HB = first ? LINE : HB "\n" LINE; first = 0
  }
  return q
}
function skip_paren(q,   depth, ch, e) {
  depth = 1
  while (q <= L) {
    ch = substr(s, q, 1)
    if (ch == "\\") { q += 2; continue }
    if (ch == "\047") { e = index(substr(s, q + 1), "\047"); if (e == 0) return L + 1; q += e + 1; continue }
    if (ch == "(") depth++
    if (ch == ")") { depth--; if (depth == 0) return q + 1 }
    q++
  }
  return L + 1
}
function dollar(q,   r, strip, d, quoted, body, nx, e) {
  nx = substr(s, q + 1, 1)
  if (nx == "(") {
    if (match(substr(s, q), /^\$\(cat[ \t]+<</)) {   # BL-324-AWK-CATHEREDOC
      r = q + RLENGTH; strip = 0
      if (substr(s, r, 1) == "-") { strip = 1; r++ }
      while (substr(s, r, 1) == " " || substr(s, r, 1) == "\t") r++
      r = hdword(r); d = HD; quoted = HQ
      if (d != "" && substr(s, r, 1) == "\n") {
        r = hdbody(r + 1, d, strip)
        if (HOK) {
          while (r <= L && substr(s, r, 1) ~ /[ \t\n]/) r++
          if (substr(s, r, 1) == ")") {
            body = HB; sub(/\n+$/, "", body)
            if (!quoted && body ~ /[$`\\]/) dyn = 1; else cur = cur body
            return r + 1
          }
        }
      }
    }
    dyn = 1
    return skip_paren(q + 2)
  }
  if (nx == "\047") {
    dyn = 1; e = q + 2
    while (e <= L) {
      if (substr(s, e, 1) == "\\") { e += 2; continue }
      if (substr(s, e, 1) == "\047") return e + 1
      e++
    }
    return L + 1
  }
  if (nx == "{") { e = index(substr(s, q), "}"); dyn = 1; return e ? q + e : L + 1 }
  if (nx ~ /[A-Za-z_]/) { dyn = 1; e = q + 1; while (e <= L && substr(s, e, 1) ~ /[A-Za-z0-9_]/) e++; return e }   # BL-324-AWK-DYNAMIC
  if (nx ~ /[0-9@*#?$!-]/) { dyn = 1; return q + 2 }
  cur = cur "$"; return q + 1
}
function dq(q,   ch, nx, e) {
  while (q <= L) {
    ch = substr(s, q, 1)
    if (ch == "\"") return q + 1
    if (ch == "\\") {
      nx = substr(s, q + 1, 1)
      if (nx == "$" || nx == "`" || nx == "\"" || nx == "\\") { cur = cur nx; q += 2; continue }
      if (nx == "\n") { q += 2; continue }
      cur = cur ch; q++; continue
    }
    if (ch == "$") { q = dollar(q); continue }
    if (ch == "`") { e = index(substr(s, q + 1), "`"); dyn = 1; q = e ? q + e + 1 : L + 1; continue }
    cur = cur ch; q++
  }
  dyn = 1; return q
}
function addmsg(t, d) {
  if (d) MBAD = 1   # BL-324-AWK-DYNMSG
  M = NM ? M "\n\n" t : t; NM++
}
function first_line(m,   n, ln, i, l) {
  n = split(m, ln, "\n")
  for (i = 1; i <= n; i++) {
    l = ln[i]
    gsub(/[ \t\r\f\v]+/, " ", l)   # BL-324-AWK-SQUEEZE
    sub(/^ /, "", l); sub(/ $/, "", l)
    if (l != "") return l
  }
  return ""
}
function commit_msg(k,   i, n, w, file, dry, j, ch, rest, dr) {
  n = cn[k]; i = 0
  while (i < n && (cw[k, i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || cw[k, i] ~ /^(if|then|else|elif|do|while|until|!|time|\{)$/)) i++   # BL-324-AWK-PREFIX
  if (i + 1 >= n || cw[k, i] !~ /(^|\/)git$/ || cw[k, i + 1] != "commit") return
  i += 2; M = ""; NM = 0; MBAD = 0; file = ""; dry = 0
  for (; i < n; i++) {
    w = cw[k, i]
    if (w == "--") break
    if (w == "--dry-run") { dry = 1; continue }   # BL-324-AWK-DRYRUN
    if (w == "--message") { i++; if (i < n) addmsg(cw[k, i], cd[k, i]); continue }
    if (substr(w, 1, 10) == "--message=") { addmsg(substr(w, 11), cd[k, i]); continue }   # BL-324-AWK-LONGEQ
    if (w == "--file") { i++; if (i < n) file = cw[k, i]; continue }
    if (substr(w, 1, 7) == "--file=") { file = substr(w, 8); continue }
    if (substr(w, 1, 1) == "-" && substr(w, 2, 1) != "-") {
      for (j = 2; j <= length(w); j++) {   # BL-324-AWK-CLUSTER
        ch = substr(w, j, 1)
        if (ch == "m" || ch == "F" || ch == "C" || ch == "c" || ch == "t") {
          rest = substr(w, j + 1); dr = cd[k, i]
          if (rest == "") { i++; if (i < n) { rest = cw[k, i]; dr = cd[k, i] } }
          if (ch == "m") addmsg(rest, dr)
          if (ch == "F") file = rest
          break
        }
        if (ch == "S" || ch == "u") break
      }
    }
  }
  if (dry) return
  if (file == "-" && NM == 0 && hk[k] == 1) addmsg(hb[k], 0)   # BL-324-AWK-STDIN
  if (MBAD || NM == 0) return
  w = first_line(M)
  if (w != "") print w
}
{ s = (NR == 1) ? $0 : s "\n" $0 }
END {
  c = 0; cn[0] = 0; nq = 0; L = length(s); p = 1; cur = ""; dyn = 0; inw = 0
  while (p <= L) {
    ch = substr(s, p, 1)
    if (ch == "\\") {
      if (substr(s, p + 1, 1) == "\n") { p += 2; continue }
      cur = cur substr(s, p + 1, 1); inw = 1; p += 2; continue
    }
    if (ch == "\047") {
      e = index(substr(s, p + 1), "\047")
      if (e == 0) { dyn = 1; inw = 1; p = L + 1; continue }
      cur = cur substr(s, p + 1, e - 1); inw = 1; p += e + 1; continue
    }
    if (ch == "\"") { inw = 1; p = dq(p + 1); continue }
    if (ch == "$") { inw = 1; p = dollar(p); continue }
    if (ch == "`") { e = index(substr(s, p + 1), "`"); dyn = 1; inw = 1; p = e ? p + e + 1 : L + 1; continue }
    if (ch == "#" && !inw) { e = index(substr(s, p), "\n"); p = e ? p + e - 1 : L + 1; continue }   # BL-324-AWK-COMMENT
    if (ch == " " || ch == "\t") { addw(); p++; continue }
    if (ch == "\n") {
      endcmd(); p++
      for (k = 1; k <= nq; k++) {
        p = hdbody(p, qd[k], qs[k])
        if (HOK && !(qq[k] == 0 && HB ~ /[$`\\]/) && !(qc[k] in hk)) { hb[qc[k]] = HB; hk[qc[k]] = 1 }   # BL-324-AWK-HEREDOC
        else hk[qc[k]] = 0
      }
      nq = 0; continue
    }
    if (ch == ";" || ch == "|" || ch == "(" || ch == ")") { endcmd(); p++; continue }
    if (ch == "&") { if (substr(s, p + 1, 1) == ">") { addw(); p += 2; continue } endcmd(); p++; continue }
    if (ch == ">") { addw(); p++; if (substr(s, p, 1) ~ /[&>|]/) p++; continue }
    if (ch == "<") {
      addw()
      if (substr(s, p, 3) == "<<<") { p += 3; continue }
      if (substr(s, p, 2) == "<<") {
        q = p + 2; st = 0
        if (substr(s, q, 1) == "-") { st = 1; q++ }
        while (substr(s, q, 1) == " " || substr(s, q, 1) == "\t") q++
        q = hdword(q)
        nq++; qc[nq] = c; qd[nq] = HD; qs[nq] = st; qq[nq] = HQ
        p = q; continue
      }
      p++; if (substr(s, p, 1) == "&") p++
      continue
    }
    cur = cur ch; inw = 1; p++
  }
  endcmd()
  for (k = 0; k <= c; k++) commit_msg(k)
}
'
_RC_NL='
'

# _reflog_commits — the commits this call made, proved from HEAD's reflog, one
# SHA per line (see the header). Nothing when the command supplies no message.
_reflog_commits() {
  local now="" log="" subjects="" h="" sel="" gs="" t="" subj=""
  subjects=$(printf '%s\n' "$CMD" | awk "$_RC_AWK" 2>/dev/null)
  [ -n "$subjects" ] || return 0
  now=$(date +%s)
  log=$(cd "$PROJECT_ROOT" && git log -g -n 50 --no-show-signature --format='%H%x09%gd%x09%gs' --date=unix HEAD 2>/dev/null)   # BL-324-NO-SHOW-SIGNATURE
  printf '%s\n' "$log" \
    | while IFS=$'\t' read -r h sel gs; do
        t="${sel##*@\{}"; t="${t%\}}"
        case "$t" in ''|*[!0-9]*) break ;; esac
        [ "$t" -ge $((now - REFLOG_WINDOW)) ] || break   # BL-324-REFLOG-WINDOW
        case "$gs" in
          "commit: "*) subj="${gs#"commit: "}" ;;
          "commit (amend): "*) subj="${gs#"commit (amend): "}" ;;
          "commit (initial): "*) subj="${gs#"commit (initial): "}" ;;
          *) continue ;;   # BL-324-REFLOG-ACTION
        esac
        [ -n "$subj" ] || continue
        case "$_RC_NL$subjects$_RC_NL" in *"$_RC_NL$subj$_RC_NL"*) printf '%s\n' "$h" ;; esac   # BL-324-REFLOG-SUBJECT
      done
}

NAMED=$(echo "$INPUT" | jq -r '.tool_response.gitOperation.commit.sha // "" | strings' 2>/dev/null)
if [ -n "$NAMED" ]; then
  case "$NAMED" in *[!0-9a-f]*) exit 0 ;; esac   # BL-324-NAMED-HEX
  # Empty unless NAMED is a commit object in this repository: nothing is written.
  SHAS=$(cd "$PROJECT_ROOT" && git rev-parse --verify --quiet "${NAMED}^{commit}" 2>/dev/null)   # BL-324-NAMED-SHA
else
  SHAS=$(_reflog_commits)
fi

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"

LEDGER="$PROJECT_ROOT/.claude/claude-commits.jsonl"
for SHA in $SHAS; do
  grep -qF "\"sha\":\"$SHA\"" "$LEDGER" 2>/dev/null && continue   # BL-324-LEDGER-ONCE
  jq -nc \
    --arg sha "$SHA" \
    --arg ts "$TS" \
    --arg sid "$SESSION_ID" \
    '{sha: $sha, timestamp: $ts, session_id: $sid, gate: "passed"}' >> "$LEDGER"
done

exit 0

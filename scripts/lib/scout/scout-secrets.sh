#!/usr/bin/env bash
# scripts/lib/scout/scout-secrets.sh — §8.2's `secrets` section: a full-history
# secret scan, projected through an explicit field ALLOWLIST.
#
# SPEC: docs/designs/2026-08-02-brownfield-adoption-v1.md §6.1 (scope: full
# history via `gitleaks git`, degrading to `gitleaks dir` off a repository),
# §6.2 (REDACTION IS A PROJECTION, NOT A FLAG — the allowlist table below is
# normative), §6.5 (the planted-secret test), §8.2 (the schema), §12-13 (the
# schema-stability assumption this file's failure modes are designed around),
# §13-V3 (the executed evidence).
#
# M5: sources nothing. See scripts/lib/scout/scout-core.sh's header.
#
# ─────────────────────────────────────────────────────────────────────────────
# THE ONE SENTENCE THIS FILE EXISTS TO IMPLEMENT
#
# Every artifact built from a gitleaks report is assembled by naming the fields
# that may appear — NEVER by passing the tool's report through, and never by
# removing the fields that may not.
#
# WHY A DENYLIST IS THE WRONG SHAPE, IN ONE MEASUREMENT. gitleaks 8.30.1 emits
# EIGHTEEN fields per finding. `--redact` covers exactly two of them, `Secret`
# and `Match`. It does NOT touch `Message` — the full commit message — and a
# key planted in a commit message therefore survives into a "redacted" report
# intact. A denylist that stripped `Secret`, `Match` and `Message` today would
# silently pass through whatever field the next gitleaks release adds. The
# allowlist has the two failure modes worth having: it fails SAFE when a field
# is added (the new field is simply never read) and LOUD when a field is
# renamed (it lands in `fieldsMissing`, which the report prints).
#
# THE SCHEMA HAS NO `secret` FIELD TO FORGET TO STRIP. That is §8.2's own
# sentence and it is the design property, not a coding convention: there is no
# code path from the tool's `Secret` value to any byte Scout writes.
#
# THE PROOF IS NOT THIS COMMENT. tests/test-brownfield-wp2-scout-sections.sh
# plants four BASE32-valid synthetic AWS keys — one in a diff, one in a commit
# MESSAGE, one carrying the message plant's commit, one inside a git hook — and
# asserts that none of them occurs in any byte of any artifact, temp residue
# included. XB neuters the one line below marked SCOUT-SECRETS-ALLOWLIST and
# watches the message plant walk out.

# ── THE ALLOWLIST (§6.2's table, and the only thing that decides) ───────────
#
# RuleID       what matched
# File         where
# Commit       when, in history terms
# Fingerprint  <commit>:<file>:<ruleid>:<startline> — the stable per-finding key
#              a disposition file joins on (§6.3)
# StartLine    locates it WITHOUT quoting it
# Date         ordering, and "is this still live"
# Description  the human-readable rule name
#
# REFUSED, each for a stated reason: Secret and Match (the value — never);
# Message (not redacted by the tool, operator-authored free text, DEMONSTRATED
# to carry a secret); Author and Email (attribution of a leak to a named person
# is the operator's decision, not a default in a committed file); Entropy,
# EndLine, EndColumn, StartColumn, SymlinkFile, Tags (not load-bearing — and
# every field kept is a field that can leak).
#
# ONE LINE, DELIBERATELY. It is the mutation target: replace it with the tool's
# full field list and the projection becomes a passthrough.
_SCOUT_SECRET_FIELDS="RuleID File Commit Fingerprint StartLine Date Description"  # SCOUT-SECRETS-ALLOWLIST

# _scout_secret_json_key FIELD — the report's key for one allowlisted field.
#
# Generic on purpose: it lower-cases the first character and keeps the rest, so
# a field ADDED to the allowlist gets a key without a second edit. If it were a
# closed table, the XB mutation would rename nothing, emit nothing, and pass
# while the projection was in fact a passthrough — the mutation has to be able
# to bite for the proof to mean anything.
_scout_secret_json_key() {
  case "$1" in
    RuleID)    printf 'ruleId' ;;
    StartLine) printf 'startLine' ;;
    *)         printf '%s%s' \
                 "$(printf '%s' "$1" | cut -c1 | tr 'A-Z' 'a-z')" \
                 "$(printf '%s' "$1" | cut -c2-)" ;;
  esac
}

# _scout_secrets_project REPORT WORK — THE PROJECTION.
#
# Reads a gitleaks JSON report and writes, into WORK:
#   secfields   `<idx>\t<Field>\t<S|N>\t<value>` for ALLOWLISTED fields only
#   secmissing  one allowlisted field name per line that the report never
#               carried (empty when the schema is what we expect)
#
# `S` marks a JSON string whose value is kept in its ORIGINAL ESCAPED FORM —
# it came out of a valid JSON string literal, so it is re-emitted verbatim
# between quotes and cannot be double-escaped or under-escaped by a round trip
# through a hand-rolled encoder. `N` marks a bare token (number, true, false,
# null), emitted unquoted.
#
# WHY A CHARACTER-LEVEL WALKER AND NOT `grep '"RuleID"'`. jq is forbidden here
# (M5), and a line-oriented parse of a pretty-printed report is a guess about
# the tool's formatter, not a parse. This walker tracks string state, escape
# state and container depth, so `Message` values containing braces, quotes or
# the literal text `"Fingerprint":` cannot be misread as structure — and a
# value nested one level deeper (a `Tags` array member) is never mistaken for a
# field of the finding.
#
# THE ALLOWLIST IS ENFORCED HERE, AT THE POINT OF EXTRACTION, not later at the
# point of rendering. A refused field is never read into a variable, never
# staged in a temp file, and never present to be leaked by a downstream bug.
#
# RETURNS NON-ZERO WHEN THE REPORT DID NOT PARSE (R-WP2-3). The walker emits a
# terminal `E ok` sentinel only when the document really was a JSON array that
# opened and closed — the first non-whitespace character was `[` and container
# depth returned to zero at EOF. Without that, a truncated or corrupt report
# (gitleaks exiting 0 having written garbage — the disk-full/truncation class)
# parsed to zero findings and was reported as `scanned` with a clean count.
# A false clean bill of health in the one section where that has a credential
# behind it is the exact silent-success class this file is written against, so
# it is now `scan-failed`. awk's own exit status is checked for the same
# reason: a walker crash must not take the clean path either.
_scout_secrets_project() {
  local report="$1" work="$2" _awkrc
  : > "$work/secfields"
  : > "$work/secmissing"
  [ -f "$report" ] || return 1

  awk -v want="$_SCOUT_SECRET_FIELDS" '
    function readstr(   body, c) {
      i++
      body = ""
      while (i <= L) {
        c = substr(buf, i, 1)
        if (c == "\\") { body = body c substr(buf, i + 1, 1); i += 2; continue }
        if (c == "\"") { i++; return body }
        body = body c; i++
      }
      return body
    }
    function readtok(   start, c) {
      start = i
      while (i <= L) {
        c = substr(buf, i, 1)
        if (c == "," || c == "}" || c == "]" || c == " " || c == "\t" || c == "\r" || c == "\n") break
        i++
      }
      return substr(buf, start, i - start)
    }
    BEGIN { n = split(want, W, " "); for (k = 1; k <= n; k++) keep[W[k]] = 1 }
    { buf = buf $0 "\n" }
    END {
      L = length(buf); i = 1; depth = 0; idx = 0; curkey = ""; awaiting = 0
      opened = 0
      while (i <= L) {
        ch = substr(buf, i, 1)
        # The document must BEGIN as a JSON array. Checking only that depth
        # returns to 0 would accept `this is not json` — no braces, depth never
        # moves — as a well-formed empty report.
        if (!opened) {
          if (ch == " " || ch == "\t" || ch == "\r" || ch == "\n") { i++; continue }
          if (ch != "[") { exit 0 }
          opened = 1
        }
        if (ch == "\"") {
          s = readstr()
          if (depth == 2 && stk[2] == "{") {
            if (awaiting == 0) { curkey = s; awaiting = 1 }
            else {
              if (curkey in keep) { printf "%d\tF\t%s\tS\t%s\n", idx, curkey, s; seen[curkey] = 1 }
              awaiting = 0; curkey = ""
            }
          }
          continue
        }
        if (ch == "{") { depth++; stk[depth] = "{"; if (depth == 2) { idx++; awaiting = 0 }; i++; continue }
        if (ch == "[") { depth++; stk[depth] = "["; i++; continue }
        if (ch == "}" || ch == "]") { if (depth > 0) depth--; i++; continue }
        if (ch == ",") { if (depth == 2 && stk[2] == "{") awaiting = 0; i++; continue }
        if (ch == ":") { i++; continue }
        if (depth == 2 && stk[2] == "{" && awaiting == 1 && index("-0123456789tfn", ch) > 0) {
          t = readtok()
          if (curkey in keep) { printf "%d\tF\t%s\tN\t%s\n", idx, curkey, t; seen[curkey] = 1 }
          awaiting = 0; curkey = ""
          continue
        }
        i++
      }
      # A field is only "missing" if there was a finding it could have been
      # missing FROM. On an empty report every field is trivially unseen, and
      # reporting seven renamed fields for a clean scan would be a loud false
      # alarm in a section whose whole value is that its alarms are true.
      if (idx > 0) for (k = 1; k <= n; k++) if (!(W[k] in seen)) printf "M\t%s\n", W[k]
      # The completion sentinel. Reached only by falling off the end of a
      # document that opened as an array and closed every container it opened.
      if (opened && depth == 0) printf "E\tok\n"
    }
  ' "$report" > "$work/secraw"
  _awkrc=$?

  grep '	F	' "$work/secraw" 2>/dev/null | sed -e 's/	F	/	/' > "$work/secfields"
  grep '^M	' "$work/secraw" 2>/dev/null | cut -f2 > "$work/secmissing"

  [ "$_awkrc" -eq 0 ] || return 1
  grep -q '^E	ok$' "$work/secraw" 2>/dev/null || return 1
  return 0
}

# _scout_secrets_render WORK — the findings array's ELEMENTS, one JSON object
# per line, into $work/secjson.
#
# Iterates the ALLOWLIST, not the report: a field that is in the data but not
# in the allowlist has already been dropped at extraction, and a field in the
# allowlist that is not in the data is simply absent from the object (and named
# in `fieldsMissing`). Key order is the allowlist's order, so two reports of
# the same findings are byte-identical.
_scout_secrets_render() {
  local work="$1" idx maxidx first f kind val line
  : > "$work/secjson"
  maxidx=$(cut -f1 < "$work/secfields" 2>/dev/null | LC_ALL=C sort -n | tail -1)
  case "$maxidx" in ''|*[!0-9]*) maxidx=0 ;; esac
  idx=1
  while [ "$idx" -le "$maxidx" ]; do
    line='{'
    first=1
    for f in $_SCOUT_SECRET_FIELDS; do
      kind=$(awk -F'\t' -v i="$idx" -v k="$f" '$1==i && $2==k { print $3; exit }' "$work/secfields")
      [ -n "$kind" ] || continue
      val=$(awk -F'\t' -v i="$idx" -v k="$f" '$1==i && $2==k { sub(/^[^\t]*\t[^\t]*\t[^\t]*\t/, ""); print; exit }' "$work/secfields")
      [ "$first" -eq 1 ] || line="$line, "
      if [ "$kind" = "N" ]; then
        line="$line\"$(_scout_secret_json_key "$f")\": $val"
      else
        line="$line\"$(_scout_secret_json_key "$f")\": \"$val\""
      fi
      first=0
    done
    line="$line}"
    printf '%s\n' "$line" >> "$work/secjson"
    idx=$((idx + 1))
  done
  return 0
}

# scout_secrets_scan ROOT WORK — fills WORK with the secrets section's data.
#
# Writes (all inside WORK, which the entry script owns and removes):
#   secstatus   scanned | tool-unavailable | scan-failed
#   secscope    full-history | working-tree-only | (empty when not scanned)
#   secversion  the tool's own version string
#   seccount    the finding count, or empty when nothing was scanned
#   secconfig   a repo-local gitleaks config path, or empty
#   secnote     a one-line honest explanation of whatever the status is
#   secjson     one JSON finding object per line (the projection)
#   secmissing  allowlisted fields the report did not carry
#
# THE STATUS VOCABULARY IS THREE WORDS BECAUSE THE CLAIMS ARE DIFFERENT.
# `scanned` with zero findings is a positive result. `tool-unavailable` is
# "nobody looked". `scan-failed` is "we looked and something went wrong".
# Collapsing any two of these into an empty findings array is the
# silent-success defect class, aimed at the one section of this report where a
# false clean bill of health has a credential behind it.
scout_secrets_scan() {
  local root="$1" work="$2"
  local _bin _mode _scope _flags _rc _version _count _cfg f

  printf 'gitleaks\n' > "$work/sectool"
  : > "$work/secjson"
  : > "$work/secmissing"
  : > "$work/secscope"
  : > "$work/seccount"
  : > "$work/secconfig"
  : > "$work/secversion"

  # SCOUT_GITLEAKS_BIN exists so the suite can point Scout at a name that is
  # not installed, and prove the tool-unavailable arm without uninstalling
  # anything on the host running the tests.
  _bin="${SCOUT_GITLEAKS_BIN:-gitleaks}"

  if ! command -v "$_bin" >/dev/null 2>&1; then
    printf 'tool-unavailable\n' > "$work/secstatus"
    printf '%s\n' "gitleaks is not installed, so NOTHING WAS SCANNED. This is not a clean result — it is the absence of a result. Install it (macOS: brew install gitleaks; other hosts: https://github.com/gitleaks/gitleaks/releases) and run Scout again before treating this project as free of committed credentials." \
      > "$work/secnote"
    return 0
  fi

  _version=$("$_bin" version 2>/dev/null | head -1 | tr -d '\r')
  printf '%s\n' "$_version" > "$work/secversion"

  # §6.1: history is the point. `gitleaks git` walks it — a key present only in
  # a superseded commit and absent from the working tree is found — and that is
  # precisely what the emitted GitLab/Bitbucket templates never do. Off a
  # repository there is no history to walk, and the scope field says so rather
  # than letting a working-tree scan be read as a history scan.
  _mode="dir"; _scope="working-tree-only"
  if command -v git >/dev/null 2>&1 \
     && git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    _mode="git"; _scope="full-history"
  fi
  printf '%s\n' "$_scope" > "$work/secscope"

  # A project's OWN gitleaks config can suppress findings entirely — measured:
  # a `.gitleaks.toml` allowlisting `AKIA[A-Z2-7]{16}` takes a two-plant
  # fixture to zero. gitleaks picks it up from the working directory, so the
  # scan honours it (that is correct — it is their configuration) and the
  # report DISCLOSES it, because a clean bill of health issued under rules
  # written by the thing being audited is a different claim from a clean scan.
  _cfg=""
  for f in .gitleaks.toml gitleaks.toml; do
    if [ -f "$root/$f" ]; then _cfg="$f"; break; fi
  done
  printf '%s\n' "$_cfg" > "$work/secconfig"

  # `--exit-code 0` makes "leaks were found" a rc of 0, so a NON-zero rc means
  # the scan itself failed and can be reported as such. Without it, findings
  # and failures are the same exit code and the honest statuses collapse.
  # `--redact` is defence in depth and is NOT what makes this safe: the field
  # allowlist is. The suite's XA1 case drops this flag alone and asserts the
  # artifacts stay clean.
  _flags="--no-banner --redact --exit-code 0"  # SCOUT-SECRETS-REDACT

  # stderr is captured, never inherited: gitleaks writes INF/WRN progress lines
  # on every run, and Scout's contract is an EMPTY stderr on a successful scan.
  ( cd "$root" 2>/dev/null || exit 2
    "$_bin" "$_mode" $_flags -f json -r "$work/gl.json" . ) \
    >"$work/gl.out" 2>"$work/gl.err"
  _rc=$?

  if [ "$_rc" -ne 0 ] || [ ! -f "$work/gl.json" ]; then
    printf 'scan-failed\n' > "$work/secstatus"
    printf '%s\n' "The secret scan did not complete (gitleaks exited $_rc). NOTHING was scanned — treat this as unknown, not as clean, and re-run Scout once the scanner works on this host." \
      > "$work/secnote"
    return 0
  fi

  # A report that exists and an exit code of 0 are NOT the same thing as a
  # report that parsed (R-WP2-3). Degrading a corrupt one to "scanned, zero
  # findings" would issue a clean bill of health on the strength of garbage.
  if ! _scout_secrets_project "$work/gl.json" "$work"; then
    : > "$work/secjson"
    : > "$work/secmissing"
    printf 'scan-failed\n' > "$work/secstatus"
    printf '%s\n' "The scanner exited cleanly but its report did not parse, so NOTHING here can be trusted — treat this as unknown, not as clean. A truncated or corrupt report is usually a full disk or a killed process; re-run Scout." \
      > "$work/secnote"
    return 0
  fi
  _scout_secrets_render "$work"
  _count=$(grep -c '' "$work/secjson" 2>/dev/null)
  case "$_count" in ''|*[!0-9]*) _count=0 ;; esac
  printf '%s\n' "$_count" > "$work/seccount"
  printf 'scanned\n' > "$work/secstatus"
  printf '%s\n' "Every finding below is built from a fixed list of seven fields. The secret VALUE is never one of them, and neither is the commit message — which the scanner does not redact and which has been demonstrated to carry one." \
    > "$work/secnote"
  return 0
}

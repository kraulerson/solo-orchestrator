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

# scout_secrets_scan ROOT WORK [RULES_POLICY] [FRAMEWORK_CONFIG]
#   — fills WORK with the secrets section's data.
#
# RULES_POLICY IS NAMED AT EVERY CALL SITE AND DEFAULTS TO THE SURVEY'S.
# There are two callers and they want opposite things, so the policy is a
# PARAMETER rather than a global or an environment seam (WP10b, §6.2b):
#
#   project   (default) — honour whatever the scanned project configures: a
#               repo-local `.gitleaks.toml`, a `.gitleaksignore`, an inline
#               `gitleaks:allow`, `GITLEAKS_CONFIG*` in the environment. This
#               is CORRECT for Scout. `## BL-288:` states the rule: a read-only
#               survey must not refuse, and a survey that overrode a project's
#               own scanner configuration would be making a claim about that
#               project under rules the project did not agree to. The report
#               DISCLOSES the config through `configFile` instead.
#   framework            — force the framework's own rules and ignore every
#               project-controlled suppressor. This is for adoption's secrets
#               STOP, which decides whether a project may be adopted and must
#               not take that decision under rules the thing being audited
#               wrote. FRAMEWORK_CONFIG is required here and is passed, not
#               looked up, so this file holds no knowledge of the framework's
#               layout.
#
# AN ENVIRONMENT SEAM WAS REJECTED FOR THIS. A variable that forces framework
# rules would be readable by the survey too, and anything that can silently
# turn the survey into a rule-overriding scan re-opens exactly what `## BL-288:`
# closed. A parameter cannot be set by accident from outside the process.
#
# Writes (all inside WORK, which the entry script owns and removes):
#   secstatus   scanned | scanned-partial | tool-unavailable | scan-failed
#   secscope    full-history | shallow-history | working-tree-only | (empty when not scanned)
#   seccommits  commits reachable from HEAD, or empty off a repository
#   secversion  the tool's own version string
#   seccount    the finding count, or empty when nothing was scanned
#   secconfig   a repo-local gitleaks config path, or empty
#   secnote     a one-line honest explanation of whatever the status is
#   secjson     one JSON finding object per line (the projection)
#   secmissing  allowlisted fields the report did not carry
#
# THE STATUS VOCABULARY IS FOUR WORDS BECAUSE THE CLAIMS ARE DIFFERENT.
# `scanned` with zero findings is a positive result. `tool-unavailable` is
# "nobody looked". `scan-failed` is "we looked and something went wrong".
# `scanned-partial` is "we looked at part of it and cannot speak for the rest"
# (BL-288 — a shallow clone). Collapsing any two of these into an empty
# findings array is the silent-success defect class, aimed at the one section
# of this report where a false clean bill of health has a credential behind it.
scout_secrets_scan() {
  local root="$1" work="$2"
  local policy="${3:-project}" fwcfg="${4:-}"
  local _bin _mode _scope _flags _rc _version _count _cfg _commits _gitdir f
  local _SCOUT_GITLEAKS_MIN="" _flr=""
  local _ignore_none=""
  local _fwflags
  _fwflags=()

  printf 'gitleaks\n' > "$work/sectool"
  : > "$work/secjson"
  : > "$work/secmissing"
  : > "$work/secscope"
  : > "$work/seccommits"
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

  # ── BL-289: A SCANNER TOO OLD TO RUN THIS SCAN IS NOT A SCANNER ──────────
  # `gitleaks git` and `gitleaks dir` — the two spellings the scan below uses —
  # are the post-8.19.0 commands. Upstream deprecated and hid `detect`/`protect`
  # in v8.19.0, and that is the release that made these the spelling. An 8.18.x
  # binary does not answer `gitleaks git`.
  #
  # WHY THIS IS `tool-unavailable` AND NOT `scan-failed`, WHICH IS THE WHOLE
  # POINT OF THE ENTRY. Without this arm the old binary errors and the scan is
  # reported `scan-failed` — and §6.1's table treats the two very differently
  # at `personal`: `scan-failed` WARNS AND CARRIES ON with no acknowledgement,
  # while `tool-unavailable` STOPS until an acceptance is recorded. A
  # contributor with an old gitleaks therefore adopted a personal project on a
  # cheerful warning where the design requires a signed acceptance. The honest
  # word for "a binary is present but cannot perform this scan" is the one that
  # means nobody looked.
  #
  # THE FLOOR IS DUPLICATED FROM `templates/tool-matrix/common.json` ON PURPOSE
  # and the duplication is PINNED: this file's header records that it sources
  # nothing (M5), and Scout must work when pointed at a project from anywhere,
  # so it cannot read the framework's matrix at runtime. `F1` in
  # `tests/test-bl289-gitleaks-version-floor.sh` asserts these two spellings
  # are the same string, so a drift is a red test rather than a silent split.
  _SCOUT_GITLEAKS_MIN="8.19.0"   # SCOUT-SECRETS-VERSION-FLOOR

  # FAIL CLOSED ON A VERSION THAT CANNOT BE READ. A binary whose version does
  # not parse has not demonstrated it meets the floor, and `## BL-147:` is the
  # standing rule: a check that cannot run must not pass. Assuming current
  # would be the fail-open direction on the one question this section exists
  # to answer honestly.
  # WHAT COUNTS AS READABLE: the LEADING `N(.N)*` PREFIX, and nothing more.
  # Three drafts of this line were wrong in three different ways, each measured
  # against a real fixture rather than reasoned about:
  #   * reading the RAW string refused a legitimate `v8.30.1` tag, because the
  #     comparison strips the `v` and the guard did not;
  #   * requiring the WHOLE stripped string to be numeric-dotted refused
  #     `9.9.9-fake` — and a gitleaks built from source really does carry a
  #     suffix, so that is a false refusal of a working scanner, which
  #     `tests/test-brownfield-wp2-scout-sections.sh` G10 caught;
  #   * accepting any string with a digit in it let `9abc` through as major 9.
  # Stripping the leading non-digit run and comparing THAT satisfies all
  # three: a suffix is ignored (awk's `+0` reads `9.9.9-fake`'s last field as
  # 9), a `v` is stripped, and a string with no digits at all leaves an empty
  # result the guard below refuses. The false-refusal risk is concrete (source
  # builds exist); the residual permissiveness — `9abc` reading as major 9 — is
  # ACCEPTED, not fixed, because it is a string no gitleaks emits.
  # SIMPLER THAN IT WAS, DELIBERATELY. A draft also extracted the leading
  # `N(.N)*` prefix with `grep -oE`. Measured: that is REDUNDANT — awk's `+0`
  # coercion below already reads `9.9.9-fake`'s third field as 9 and `9abc` as
  # 9, so the extraction changed no outcome on any input and its mutant
  # survived. Dropped rather than kept as decoration.
  # `2>/dev/null`: BSD sed errors with `RE error: illegal byte sequence` on a
  # version string carrying invalid UTF-8. The behaviour is already right — the
  # result is empty and the guard refuses — but Scout's contract is an EMPTY
  # stderr on a successful scan, and this would leak onto it.
  _flr=$(printf '%s' "$_version" | sed 's/^[^0-9]*//' 2>/dev/null)
  if [ -z "$_flr" ]; then
    printf 'tool-unavailable\n' > "$work/secstatus"
    printf '%s\n' "A gitleaks binary was found but its version could not be read (it reported '${_version:-nothing at all}'), so there is no way to tell whether it can perform this scan. NOTHING WAS SCANNED — this is not a clean result, it is the absence of one. gitleaks ${_SCOUT_GITLEAKS_MIN} or newer is required, because the git-history scan this runs uses subcommands that older releases do not have. If you built gitleaks from source with 'go install' or a plain 'go build', the version is left unstamped and reads as 'version is set by build process' — rebuild with 'make build', which stamps it, or install a release binary." \
      > "$work/secnote"
    return 0
  fi

  # `awk`, not a shell loop: this file must run on bash 3.2 and the comparison
  # needs no arrays, no `IFS` tampering (which semgrep's
  # `bash.lang.security.ifs-tampering` rule flags) and no subshell arithmetic.
  # Leading non-digits are stripped first so a `v8.19.0` tag compares as
  # 8.19.0 rather than as a zero major.
  if awk -v a="$_flr" -v b="$_SCOUT_GITLEAKS_MIN" 'BEGIN{
        na=split(a,A,"."); nb=split(b,B,".");
        m=(na>nb)?na:nb;
        for(i=1;i<=m;i++){
          x=(i<=na)?A[i]+0:0; y=(i<=nb)?B[i]+0:0;
          if(x<y) exit 0;
          if(x>y) exit 1;
        }
        exit 1 }'; then
    printf 'tool-unavailable\n' > "$work/secstatus"
    printf '%s\n' "The gitleaks on this host is ${_version}, and this scan needs ${_SCOUT_GITLEAKS_MIN} or newer: the git-history scan uses the 'gitleaks git' subcommand, which releases before ${_SCOUT_GITLEAKS_MIN} do not have. NOTHING WAS SCANNED — treat this as unknown, not as clean. Upgrade gitleaks (macOS: brew upgrade gitleaks; other hosts: https://github.com/gitleaks/gitleaks/releases) and scan again before treating this project as free of committed credentials." \
      > "$work/secnote"
    return 0
  fi

  # §6.1: history is the point. `gitleaks git` walks it — a key present only in
  # a superseded commit and absent from the working tree is found — and that is
  # precisely what the emitted GitLab/Bitbucket templates never do. Off a
  # repository there is no history to walk, and the scope field says so rather
  # than letting a working-tree scan be read as a history scan.
  #
  # A SHALLOW CLONE IS THE SAME LIE WITH A REPOSITORY UNDERNEATH IT.  # BL-288-SHALLOW-SCOPE
  # `gitleaks git` walks what git HAS, and a `--depth 1` checkout has one
  # commit. It reads it, finds nothing, and exits 0 — there is no error for the
  # 3,652 commits it was never given. The scan is not what is wrong here; the
  # CLAIM is. Measured before this arm existed: a three-commit fixture whose
  # first commit adds an AKIA key and whose second removes it reports
  # findingCount 1 from a full clone and `scanned / full-history / 0` from a
  # `--depth 1` clone of the same repository — a clean bill of health over a
  # live credential, issued under the word "full". `# BL-147` states the
  # framework's own rule for this shape: a check that cannot run must not pass.
  _mode="dir"; _scope="working-tree-only"; _commits=""
  if command -v git >/dev/null 2>&1 \
     && git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    _mode="git"; _scope="full-history"
    # `--is-shallow-repository` is the reading that also holds inside a linked
    # worktree, where the `shallow` marker lives in the MAIN git directory and
    # `--absolute-git-dir` points at `.git/worktrees/NAME` instead. The file
    # test is the fallback for a git too old to answer, and it is absolute
    # because a relative `.git/shallow` would be resolved against Scout's cwd
    # rather than against the project it was pointed at.
    _gitdir=$(git -C "$root" rev-parse --absolute-git-dir 2>/dev/null)
    if [ "$(git -C "$root" rev-parse --is-shallow-repository 2>/dev/null)" = "true" ] \
       || { [ -n "$_gitdir" ] && [ -f "$_gitdir/shallow" ]; }; then
      _scope="shallow-history"
    fi
    _commits=$(git -C "$root" rev-list --count HEAD 2>/dev/null)
    case "$_commits" in ''|*[!0-9]*) _commits="" ;; esac
  fi
  printf '%s\n' "$_scope" > "$work/secscope"
  printf '%s\n' "$_commits" > "$work/seccommits"

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

  # ── THE FRAMEWORK-RULES ARM (WP10b, §6.2b) ────────────────────────────────
  # Four suppressors, four answers, and each was MEASURED on 8.30.1 rather
  # than assumed (§13-V35, and re-measured while building this):
  #
  #   .gitleaks.toml / gitleaks.toml at the scanned root  -> `-c` outranks it
  #   GITLEAKS_CONFIG / GITLEAKS_CONFIG_TOML in the env   -> `-c` outranks it,
  #        AND they are unset in the subshell, because relying on precedence
  #        alone means one dropped flag restores the whole vector
  #   an inline `gitleaks:allow` comment                  -> --ignore-gitleaks-allow
  #   a .gitleaksignore                                   -> --gitleaks-ignore-path
  #
  # THE LAST ONE IS THE SUBTLE ONE AND IT IS WHY THE CWD MATTERS. gitleaks
  # resolves `--gitleaks-ignore-path` against the PROCESS cwd, default `.`.
  # Adoption scans a no-checkout clone whose working tree is EMPTY, so no
  # ignore file can exist there — but only if the scan's cwd is the clone. The
  # `cd "$root"` below is what delivers that, with the clone passed as ROOT.
  #
  # THE FLAG IS REDUNDANT TODAY AND IT STAYS ANYWAY — said plainly because a
  # reader who measures it will find it so and should not have to wonder. With
  # cwd = an empty working tree there is no `.gitleaksignore` for gitleaks to
  # read, so dropping `--gitleaks-ignore-path` alone changes no result and NO
  # mutation of it dies. §6.2b calls the cwd load-bearing and pins it with
  # WP10b's proof (2); that is true of an implementation with ONE defence, and
  # this has two. Each alone suffices, which is why neither alone has a
  # discriminating mutant — measured, not assumed. The pair is kept because the
  # day someone changes what ROOT points at, the flag is what still holds.
  #
  # THE INLINE-ALLOW CASE IS NOT COVERED BY THE EMPTY WORKING TREE, which is
  # the trap a first reading of §6.2b walks into: the comment lives in the
  # history BLOB, and a history walk reads blobs regardless of what is checked
  # out. Measured on a two-plant fixture — 1 finding without the flag, 2 with.
  if [ "$policy" = "framework" ]; then
    # AN EMPTY `$fwcfg` IS THE DANGEROUS ONE, NOT THE MISSING FILE. A missing
    # path makes gitleaks exit 1, which surfaces as `scan-failed` even with no
    # guard here. An EMPTY one does not: measured on 8.30.1, `-c ""` behaves
    # exactly as if no `-c` were given — it resumes normal config discovery and
    # honours the scanned tree's own `.gitleaks.toml` (0 findings against 2).
    # That is the silent fallback to the audited project's rules that this
    # whole policy exists to refuse, so the guard covers BOTH shapes and case
    # O9 in tests/test-brownfield-wp10b-own-scan.sh pins it.
    if [ -z "$fwcfg" ] || [ ! -f "$fwcfg" ]; then
      # FAIL LOUDLY. Falling back to the project's rules here would be the
      # silent-success shape: the stop would decide under exactly the rules it
      # exists to ignore, and say nothing.
      printf 'scan-failed\n' > "$work/secstatus"
      printf '%s\n' "The scan was asked to use the framework's own rules and that config could not be read (${fwcfg:-no path given}). NOTHING was scanned — treat this as unknown, not as clean." \
        > "$work/secnote"
      return 0
    fi
    _ignore_none="$work/no-ignore-here"
    mkdir -p "$_ignore_none" 2>/dev/null
    # AN ARRAY, NOT A STRING, AND THAT IS NOT STYLE. `$_flags` above is
    # word-split on purpose and may be, because it holds no paths. These flags
    # DO: the framework config and the ignore directory are absolute paths, and
    # this framework's own checkout lives under `Claude Projects` — a directory
    # with a SPACE in it. Appended to `$_flags`, the config path split in two
    # and gitleaks answered `unknown flag`, which this function then reported
    # as `scan-failed` — a stop at organizational, from a quoting bug, on every
    # host whose checkout path contains a space. Measured before it was fixed.
    _fwflags=( -c "$fwcfg" --ignore-gitleaks-allow --gitleaks-ignore-path "$_ignore_none" )   # SCOUT-SECRETS-FRAMEWORK-RULES
  fi

  # stderr is captured, never inherited: gitleaks writes INF/WRN progress lines
  # on every run, and Scout's contract is an EMPTY stderr on a successful scan.
  #
  # `cd "$root"` IS LOAD-BEARING UNDER THE FRAMEWORK POLICY, not just tidy —
  # see the `--gitleaks-ignore-path` note above. A build that scanned the clone
  # from the adoptee's cwd reads the adoptee's `.gitleaksignore` and finds one
  # plant fewer.
  ( cd "$root" 2>/dev/null || exit 2
    if [ "$policy" = "framework" ]; then
      unset GITLEAKS_CONFIG GITLEAKS_CONFIG_TOML
    fi
    "$_bin" "$_mode" $_flags ${_fwflags[@]+"${_fwflags[@]}"} -f json -r "$work/gl.json" . ) \
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
  # BL-288: `scanned-partial` is a FOURTH status word, not a flag beside the
  # third, because the three-word vocabulary above is what consumers switch on
  # and both of adoption's readers spell that switch `[ "$status" != "scanned" ]`.
  # A boolean sibling would have left every one of them reading a shallow scan
  # as a completed one. The findings it did produce are real and are still
  # emitted; what the word withdraws is the claim that zero means zero.
  if [ "$_scope" = "shallow-history" ]; then
    printf 'scanned-partial\n' > "$work/secstatus"
    printf '%s\n' "This is a SHALLOW clone. Git has only ${_commits:-an unknown number of} commit(s) of this project here, so the scanner read those and NOTHING ELSE — and a credential that was committed and later removed lives precisely in the part it could not read. A count of zero means zero in the commits present; it is not a statement about this project's history. Run 'git remote set-branches origin '*' && git fetch --unshallow' and scan again before treating this project as free of committed credentials. (--depth narrows the REFSPEC as well as the history, so --unshallow ALONE re-reads only the branch you cloned.)" \
      > "$work/secnote"
    return 0
  fi
  printf 'scanned\n' > "$work/secstatus"
  printf '%s\n' "Every finding below is built from a fixed list of seven fields. The secret VALUE is never one of them, and neither is the commit message — which the scanner does not redact and which has been demonstrated to carry one." \
    > "$work/secnote"
  return 0
}

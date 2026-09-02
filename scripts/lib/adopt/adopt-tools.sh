#!/usr/bin/env bash
# scripts/lib/adopt/adopt-tools.sh — Act 2's SECOND step: tool resolution, and
# the §6.2 re-scan it makes possible.
#
# SPEC: docs/designs/2026-08-23-brownfield-adoption-v2.md §6.2 (tool resolution
# makes the scanner guaranteed), §8.2 step 2 (its position), §10-WP10.
#
# ─────────────────────────────────────────────────────────────────────────────
# WHAT THIS FILE IS FOR, IN ONE SENTENCE. Scout may have run before gitleaks
# was installed, so the report Act 2 consumes can say "nobody looked" about a
# host where somebody now can — this step installs the scanner and asks again.
#
# WHAT IT DELIBERATELY DOES NOT DO. It makes no stop/proceed decision. §6.1's
# tier table, §6.3's dispositions and §6.4's tiered escape are WP10b's, and a
# `tool-unavailable` result still completes an adoption here exactly as it did
# before this package. Deciding anything on the status in this file would move
# a boundary §10 draws.
#
# ─────────────────────────────────────────────────────────────────────────────
# THE POSITION IS THE CONSTRAINT (§8.2). Step 2 is BEFORE the secrets check
# that reads its result and BEFORE any writer: a run abandoned here has changed
# the repository not at all, and the host only if the operator said yes.
#
# bash-3.2 safe: no associative arrays, no `${var,,}`, no `((x++))`.

# ── THE RESOLVER SEAM ───────────────────────────────────────────────────────
# The shipped resolver probes the HOST, which makes it the wrong thing for a
# test to drive: a suite that let it run would assert one thing on a laptop
# with gitleaks and another on a runner without it (CLAUDE.md's local-vs-CI
# divergence), and its install arm would install software on whatever machine
# ran the tests. `SOIF_ADOPT_RESOLVER` names an alternative executable so the
# suite can hand this function the exact JSON the real resolver was MEASURED to
# emit for each case. It defaults to the real one, so nothing changes in use.
_adopt_resolver_path() {
  if [ -n "${SOIF_ADOPT_RESOLVER:-}" ]; then
    printf '%s\n' "$SOIF_ADOPT_RESOLVER"
  else
    printf '%s\n' "$ADOPT_FRAMEWORK_ROOT/scripts/resolve-tools.sh"
  fi
}

# _adopt_tools_language REPORT — the dominant language Scout detected, or a
# neutral default. The resolver needs one; guessing loudly is worse than a
# default, so an absent or unreadable stack yields the same value a scaffolded
# project with no language would use.
_adopt_tools_language() {
  local report="$1" lang
  lang="$(adopt_report_read "$report" '[.stack.languages[]? | .name] | first // ""')"
  case "$lang" in ''|null) printf 'other\n' ;; *) printf '%s\n' "$lang" ;; esac
}

_adopt_tools_devos() {
  case "$(uname -s 2>/dev/null)" in
    Darwin) printf 'darwin\n' ;;
    Linux)  printf 'linux\n' ;;
    *)      printf 'linux\n' ;;
  esac
}

# ── IS THIS STRING SOMETHING TO RUN? ────────────────────────────────────────
# THE MATRIX SHIPS BOTH COMMANDS AND DOCUMENTATION, AND THE DIFFERENCE IS NOT
# COSMETIC. `common.json`'s gitleaks entry carries `darwin_brew`, three linux
# recipes AND a `manual` key whose value is
# `https://github.com/gitleaks/gitleaks/releases`. MEASURED against the shipped
# resolver: darwin with brew returns `brew install gitleaks`; with brew ALSO
# absent it returns that URL — and, because `manual` is the last entry in the
# resolver's own `INSTALL_KEYS`, the URL arrives in the **auto_install** bucket
# rather than the manual one. A consumer that pipes it to a shell executes a
# URL. `init.sh` has the same exposure through the same field; that is a defect
# in the shared resolver with a wider blast radius than this package, filed on
# `## BL-242:` rather than fixed from here, because §10 authorises WP10 to
# INVOKE the resolver, not to change it.
#
# A FIRST CUT RESOLVED THE FIRST WORD AS A COMMAND AND THAT WAS WRONG ON LINUX.
# The matrix's linux_apt/dnf/pacman values are ARRAYS, which the resolver joins
# with ` && `, so the first token is `GITLEAKS_VERSION=$(curl` — not a command.
# The guard therefore refused the only Linux install path the matrix has, told
# the operator "this host has no package manager recipe for it" while printing
# that recipe, and left §6.2's "tool resolution makes the scanner guaranteed"
# false on every Linux host. A cleverer head-parse does not rescue it: the
# string genuinely cannot be classified by its first word.
#
# WHAT IS LEFT IS A NARROW, TRUE TEST — a shell command never begins with a URL
# scheme — BACKED BY A BEHAVIOURAL ONE. `_adopt_tool_present` re-probes after
# the install, so even a string this misjudges cannot produce a false
# "installed" claim. Syntax refuses the one shape the matrix is measured to
# produce; behaviour catches everything else.
_adopt_cmd_is_runnable() {
  local cmd="$1"
  [ -n "$cmd" ] || return 1
  case "$cmd" in
    http://*|https://*|ftp://*|www.*) return 1 ;;
  esac
  return 0
}

# _adopt_tool_present NAME — is the tool actually on PATH now?
#
# THE INSTALL'S EXIT STATUS IS NOT EVIDENCE. A recipe whose last stage exits 0
# — a package manager that no-ops, a `curl | tar` that unpacks nothing, a
# binary landing somewhere not on PATH — produces a zero exit and no tool. A
# first cut printed "$name installed." on that exit status alone, which is the
# same "an exit code is not a receipt" shape this repository has paid for
# elsewhere.
_adopt_tool_present() {
  local name="$1"
  [ -n "$name" ] || return 1
  command -v "$name" >/dev/null 2>&1
}

# ── Step 2 ──────────────────────────────────────────────────────────────────
# adopt_resolve_tools ROOT REPORT
#
# Returns 0 in every case it handles, INCLUDING the ones where the scanner ends
# up absent. That is not leniency: §6.1's table is what decides whether an
# unscanned project may be adopted, and it lands in WP10b. This step's job is
# to remove the avoidable causes.
adopt_resolve_tools() {
  local root="$1" report="$2"
  local resolver out lang devos name cmd

  resolver="$(_adopt_resolver_path)"
  adopt_head "Making sure the tools this needs are here"

  if [ ! -x "$resolver" ] && [ ! -f "$resolver" ]; then
    adopt_note "The tool resolver is not where it should be ($resolver), so this step could not"
    adopt_note "check what is installed. Nothing was changed on this machine."
    # STILL RE-SCAN. A broken framework checkout is not evidence about the
    # HOST: gitleaks may well be installed, and a first cut returned here
    # without asking, losing a legitimate refresh.
    _adopt_rescan_secrets "$root" "$report"
    return 0
  fi

  lang="$(_adopt_tools_language "$report")"
  devos="$(_adopt_tools_devos)"

  # `--platform web` and `--track standard` are the neutral values a project
  # with no intake answer uses. Adoption HAS no platform answer — the reverse
  # intake asks only scan-derived confirmations (A7) — and inventing one would
  # be a guess in a field the resolver keys install recipes off.
  out="$( "$resolver" \
            --dev-os "$devos" \
            --platform web \
            --language "$lang" \
            --track standard \
            --phase 2 \
            --matrix-dir "$ADOPT_FRAMEWORK_ROOT/templates/tool-matrix" 2>/dev/null )" || out=""

  if [ -z "$out" ]; then
    adopt_note "The tool resolver did not produce a result, so this step could not check what is"
    adopt_note "installed. Nothing was changed on this machine."
    _adopt_rescan_secrets "$root" "$report"
    return 0
  fi

  # SELECT ON NAME **OR** CATEGORY — an unordered disjunction, not a priority
  # order; a draft of this comment said "name first, category second" while the
  # line beside it said the opposite and the code did neither. A first cut matched
  # `.category | test("ecret")`, which also matches `Secrets Management` — so
  # an unrelated installed tool in an adjacent category made this announce
  # "already installed" and skip the bucket where gitleaks was actually
  # sitting, in the same payload. The scanner has a name; use it.
  if printf '%s' "$out" | jq -e '[.already_installed[]? | select((.name // "") == "gitleaks" or (.category // "") == "Secret Detection")] | length > 0' >/dev/null 2>&1; then
    adopt_note "Secret detection: already installed. The history scan can run."
    _adopt_rescan_secrets "$root" "$report"
    return 0
  fi

  name="$(printf '%s' "$out" | jq -r '[.auto_install[]?, .manual_install[]? | select((.name // "") == "gitleaks" or (.category // "") == "Secret Detection")] | first | .name // ""' 2>/dev/null)"
  # `install_cmd` in the auto bucket, `instructions` in the manual one — the
  # resolver writes DIFFERENT FIELD NAMES per bucket
  # (`--arg instructions "$INSTALL_CMD"` … `{name, category, instructions, …}`),
  # and a first cut read only the first, so the manual arm printed
  # "see the tool matrix" instead of the reference it had been handed.
  cmd="$(printf '%s' "$out" | jq -r '[.auto_install[]?, .manual_install[]? | select((.name // "") == "gitleaks" or (.category // "") == "Secret Detection")] | first | (.install_cmd // .instructions // "")' 2>/dev/null)"
  # THE BUCKET IS THE PRIMARY CLASSIFIER, not the string. `manual_install` is
  # the resolver saying "this host cannot install it", whatever the payload
  # looks like.
  local in_manual=0
  printf '%s' "$out" | jq -e '[.manual_install[]? | select((.name // "") == "gitleaks" or (.category // "") == "Secret Detection")] | length > 0' >/dev/null 2>&1 && in_manual=1

  if [ -z "$name" ]; then
    adopt_note "Secret detection: the tool matrix named nothing for this host, so nothing was"
    adopt_note "installed. The scan will report what it can."
    _adopt_rescan_secrets "$root" "$report"
    return 0
  fi

  if [ "$in_manual" -eq 1 ] || ! _adopt_cmd_is_runnable "$cmd"; then   # BL-242-RESOLVER-NO-EXEC
    # The matrix's `manual` fallback lands here — a documentation URL, not a
    # command. Print it as a reference and never as something to run.
    adopt_note "Secret detection ($name) is not installed, and this host has no package manager"
    adopt_note "recipe for it — so adoption cannot install it for you. Install it yourself:"
    adopt_note "  ${cmd:-see the tool matrix}"
    adopt_note "Then run adoption again to scan this project's history."
    _adopt_rescan_secrets "$root" "$report"
    return 0
  fi

  adopt_blank
  adopt_note "$name is not installed. It is what reads your git history for committed"
  adopt_note "credentials, and without it this adoption cannot tell you whether there are any."
  adopt_blank
  # THE COMMAND IS SHOWN BEFORE THE QUESTION, NOT AFTER THE ANSWER. A first cut
  # printed it only once the operator had already agreed, which is consent to
  # `eval` a string they had not seen.
  adopt_note "This would run, exactly as written:"
  adopt_note "  $cmd"
  # THE ANSWER WORDING AVOIDS THE LITERAL `install ` ON PURPOSE. `## BL-225:`'s
  # T9 is a DENYLIST over write verbs — `install ` among them — anchored to
  # exclude output functions by first token but not `adopt_ask_choice`'s
  # arguments. A first cut offered "install it now" and T9 flagged two lines of
  # prose as unmarked writers. Weakening that denylist so this package could
  # phrase an answer differently would be the wrong trade: it catches new
  # writers by default, and that default is worth more than these two words.
  if ! adopt_ask_choice "setting up $name" "Set $name up now?" \
        "set it up now" "skip it"; then
    return 1
  fi
  case "$ADOPT_ANSWER" in
    "set it up now")
      # ── cd INTO THE RUN'S OWN WORK DIR FIRST ────────────────────────────
      # `eval` inherits the adoptee's directory as cwd, so a recipe writing a
      # relative path writes into the OPERATOR'S REPOSITORY — measured: an
      # installer left two untracked files in the adoptee while `adopt_refuse`
      # went on to say "Nothing was committed and nothing was written". Real
      # matrix recipes do this (`npm init playwright@latest`, gitleaks'
      # from-source `git clone` path). `## BL-225:`'s T9 is a STATIC check over
      # the driver's own writer calls and cannot see through an `eval`, which
      # is why it passed while the claim was false.
      #
      # `adopt_touched_disk` is called unconditionally BEFORE the eval, because
      # the driver cannot know what an arbitrary recipe writes — the honest
      # position is that from here on, something may have been.
      adopt_touched_disk   # BL-225-TOUCHED-DISK
      # `</dev/null` IS NOT TIDINESS. The eval inherits fd 0 — the same open
      # file description `adopt_stdin_init`'s `exec 3<&0` reads the operator's
      # answers from — so an installer that reads stdin CONSUMES THEM.
      # Measured with a recipe of `read a; read b`: it swallowed two
      # confirmations and the adoption then ran out of answers and aborted.
      # Latent with today's matrix (neither gitleaks recipe reads stdin; `sudo`
      # uses /dev/tty) and live the moment an eval-reachable recipe prompts —
      # `npm init playwright@latest`, named in this file already, is one.
      # Detaching stdin also means an interactive installer fails fast instead
      # of hanging on a prompt this run has redirected to /dev/null.
      if ( cd "$ADOPT_WORK" 2>/dev/null && eval "$cmd" ) </dev/null >/dev/null 2>&1; then   # BL-242-RESOLVER-INSTALL
        :
      fi
      # VERIFIED, NOT ASSERTED (`# BL-242-RESOLVER-VERIFY`). The exit status of
      # an install recipe is not evidence the tool is there.
      if _adopt_tool_present "$name"; then   # BL-242-RESOLVER-VERIFY
        adopt_note "$name is installed and on PATH."
      else
        # NOT "nothing else was changed" — the driver cannot know that. The
        # comment ten lines above says so in as many words ("the driver cannot
        # know what an arbitrary recipe writes"), and a recipe that created a
        # directory outside the project then drew exactly that false claim.
        # This is the shape round 1 blocked, relocated to the failure branch.
        adopt_note "That did not put $name on PATH. Whatever the command did to this machine, it"
        adopt_note "did not leave $name where the scan can find it, so the scan will report that"
        adopt_note "nothing looked at your history."
      fi
      ;;
    *)
      adopt_note "Skipped. The scan will report that nothing looked at your history."
      ;;
  esac
  _adopt_rescan_secrets "$root" "$report"
  return 0
}

# ── §6.2's re-scan ──────────────────────────────────────────────────────────
# _adopt_rescan_secrets ROOT REPORT
#
# WHY IT IS CONDITIONAL. A report that already says `scanned` is the one Act 2
# consumed and is about to record an evidence hash for; re-running the scanner
# over it would cost a full history walk and replace the measurement the stamp
# names with a different one. Only a report that says nobody looked is worth
# asking again.
#
# WHY IT REUSES SCOUT'S OWN TWO FUNCTIONS AND RE-IMPLEMENTS NOTHING.
# `scout_secrets_scan` performs the field-allowlist projection AT EXTRACTION
# TIME, and `_scout_emit_secrets` renders only what that projection produced —
# scout-report.sh's own comment says it "does not see field names, does not
# choose which to print, and has no access to anything the allowlist refused".
# A second renderer here would be a second chance to leak a secret's value into
# a committed artifact. There is exactly one projection and this calls it.
# Set by _adopt_rescan_secrets when — and only when — it produced a refreshed
# report. Empty otherwise, so `adopt_main`'s switch is a no-op on every path
# that did not re-scan.
ADOPT_REPORT_REFRESHED=""

_adopt_rescan_secrets() {
  local root="$1" report="$2"
  local status work sec

  status="$(adopt_report_read "$report" '.secrets.status // ""')"
  [ "$status" != "scanned" ] || return 0   # BL-242-SECRETS-RESCAN

  # THREE LIBRARIES, NOT TWO, and the third is the one a first cut missed.
  # `_scout_emit_secrets` renders through `scout_json_str`,
  # `scout_json_str_or_null` and `scout_json_array_from_file`, all of which
  # live in `scout-core.sh` — Scout's own entry script sources it first for
  # exactly this reason. Without it the renderer emits syntactically invalid
  # JSON with every value blank (`"tool": ,`), which the splice below then
  # refuses, so the failure was SILENT: the report kept its stale section and
  # the run said the re-scan had happened. Measured before it was fixed.
  local core_lib="$ADOPT_FRAMEWORK_ROOT/scripts/lib/scout/scout-core.sh"
  local secrets_lib="$ADOPT_FRAMEWORK_ROOT/scripts/lib/scout/scout-secrets.sh"
  local report_lib="$ADOPT_FRAMEWORK_ROOT/scripts/lib/scout/scout-report.sh"
  # EVERY EARLY RETURN SAYS WHY. A first cut had five failure arms and only
  # ONE of them spoke — and the silent four included the exact condition the
  # commit message narrated as fixed (a missing `scout-core.sh`), because the
  # existence guard short-circuits before the render arm ever runs. A re-scan
  # that does not happen and says nothing leaves the operator reading a stale
  # section as if it were current.
  if [ ! -f "$core_lib" ] || [ ! -f "$secrets_lib" ] || [ ! -f "$report_lib" ]; then
    adopt_note "The scan could not be re-run — this framework checkout is missing part of Scout,"
    adopt_note "so the secrets section is still the one the survey produced."
    return 0
  fi

  if ! work="$(mktemp -d "${TMPDIR:-/tmp}/adopt-rescan.XXXXXXXX" 2>/dev/null)"; then
    adopt_note "The scan could not be re-run — no temporary directory could be created. The"
    adopt_note "secrets section is still the one the survey produced."
    return 0
  fi

  # A SUBSHELL, because these two libraries are Scout's and sourcing them into
  # the driver's shell would put their helpers in scope for every later step —
  # the module-boundary problem `scripts/lint-module-dependencies.sh` exists to
  # police. What comes back is a string.
  sec="$(
    # shellcheck source=/dev/null
    . "$core_lib" >/dev/null 2>&1 || exit 1
    # shellcheck source=/dev/null
    . "$secrets_lib" >/dev/null 2>&1 || exit 1
    # shellcheck source=/dev/null
    . "$report_lib" >/dev/null 2>&1 || exit 1
    scout_secrets_scan "$root" "$work" >/dev/null 2>&1 || exit 1
    _scout_emit_secrets "$work" 2>/dev/null || exit 1
  )" || sec=""
  rm -rf "$work" 2>/dev/null

  if [ -z "$sec" ]; then
    adopt_note "The scan could not be re-run — the scanner or its renderer did not produce a"
    adopt_note "result. The secrets section is still the one the survey produced."
    return 0
  fi

  # `_scout_emit_secrets` emits `"secrets": { … },` — a trailing comma and all,
  # because it is written to sit inside the report's object. Splice it in with
  # jq rather than by text, so a malformed render cannot corrupt the report.
  local new_obj
  new_obj="$(printf '{%s"_end": null}' "$sec" | jq -c '.secrets // empty' 2>/dev/null)" || new_obj=""
  if [ -z "$new_obj" ]; then
    # FAIL LOUDLY RATHER THAN LEAVE A STALE SECTION SILENTLY. This arm caught a
    # missing `scout-core.sh` during the build; without it the run reported a
    # re-scan that had not happened, which is the silent-success class this
    # package exists inside.
    adopt_note "The re-scan could not be rendered, so this project's secrets section is still the"
    adopt_note "one the survey produced. Nothing was overwritten."
    return 0
  fi

  # ── THE REFRESHED REPORT IS A NEW FILE IN THE RUN'S OWN WORK DIR ─────────
  # NOT an in-place rewrite of the report the operator handed us. Two reasons,
  # and the first is an invariant this package would otherwise have broken:
  #
  # (1) `## BL-225:`'s T9 requires every write into the adoptee's tree to be
  #     preceded by `adopt_touched_disk`, so a refusal can say truthfully
  #     whether anything was written. A first cut wrote the report in place and
  #     T9 caught it — correctly. `$ADOPT_WORK` is already exempt there, with a
  #     reason on the record ("the driver's own state, not the operator's
  #     tree"), so refreshing into it satisfies the invariant by construction
  #     rather than by an exemption argued for this package.
  # (2) THE CONSUMED REPORT IS AN INPUT. Rewriting a file the operator passed
  #     on the command line — possibly Scout's output directory, possibly
  #     something they keep — is a side effect nobody asked for, and it would
  #     make a re-run of adoption non-reproducible from the same inputs.
  #
  # §6.2 asks that "the persisted copy reflects what was actually acted on";
  # `ADOPT_REPORT_REFRESHED` is how the rest of the run learns which file that
  # is, and `adopt_main` switches to it immediately after this step.
  local fresh="$ADOPT_WORK/scout-report-refreshed.json"
  if jq --argjson s "$new_obj" '.secrets = $s' "$report" > "$fresh" 2>/dev/null \
     && [ -s "$fresh" ]; then
    ADOPT_REPORT_REFRESHED="$fresh"
    # ── SAY WHAT THE RE-SCAN FOUND, NOT THAT IT RAN ───────────────────────
    # A first cut printed "this project's history was read rather than
    # skipped" whenever the SPLICE succeeded — including when the refreshed
    # status was still `tool-unavailable`. Measured, three lines apart in one
    # run: "adoption cannot install it for you" and then "your history was
    # read", over a persisted record saying `"status": "tool-unavailable",
    # "note": "…NOTHING WAS SCANNED."` A false all-clear on the one surface
    # this package exists to make trustworthy, and — before the Linux fix
    # above — the DEFAULT experience there.
    local fresh_status
    fresh_status="$(printf '%s' "$new_obj" | jq -r '.status // ""' 2>/dev/null)"
    case "$fresh_status" in   # BL-242-RESCAN-HONEST
      scanned)
        adopt_note "The scan was re-run now that the tools are resolved: this project's history"
        adopt_note "was read." ;;
      tool-unavailable)
        adopt_note "The scan was re-run and STILL could not look: the scanner is not installed."
        adopt_note "Nothing is known about credentials in this project's history." ;;
      scan-failed)
        adopt_note "The scan was re-run and it FAILED. Nothing is known about credentials in this"
        adopt_note "project's history — a scan that broke is not a scan that found nothing." ;;
      *)
        adopt_note "The scan was re-run; its status is '${fresh_status:-unknown}'." ;;
    esac
  else
    # THE SIXTH EXIT, AND A FIRST CUT COUNTED FIVE. The scan RAN — measured at
    # 755 bytes of refreshed secrets section — and the splice then failed
    # (reachable: `adopt_obtain_report` only checks `[ -f ]`, so a report that
    # is not valid JSON reaches here), after which the run said nothing at all
    # and the operator was told the survey's stale answer instead. Throwing
    # away a completed security scan in silence is the class this package sits
    # inside; counting the arms and fixing "all five" is how it survived.
    adopt_note "The scan was re-run, but its result could not be merged into this project's"
    adopt_note "report — the report file may not be valid JSON. The secrets section is still"
    adopt_note "the one the survey produced, and what the re-scan found was discarded."
  fi
  return 0
}

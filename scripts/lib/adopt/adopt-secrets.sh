#!/usr/bin/env bash
# scripts/lib/adopt/adopt-secrets.sh — §6.1's tier-scoped secrets decision.
#
# SPEC: ADOPT-002-ARCH v2.2 §6.1 (the five status rows and what each tier does
# with them), §6.1a (the `scanned-partial` row, RULED by Karl 2026-09-16),
# §6.3 (the dispositions and their record), §6.2b (the scan this decides on),
# §8.1 (block vs refuse), §8.2 step 3 (where it sits).
#
# ─────────────────────────────────────────────────────────────────────────────
# THE ONE SENTENCE THIS FILE EXISTS TO IMPLEMENT
#
# Whether adoption may proceed past a secrets result is a function of TWO
# things and nothing else: the tier the operator declared, and the status the
# stop's OWN scan produced. Never the host, never a handed-in report, never a
# flag.
#
# WHY THE TABLE IS SPELLED AS A TABLE. Five statuses times two tiers is ten
# answers, and four of the ten differ from their row-mate. Written as nested
# `if`s the differences hide; written as `case "$tier:$status"` every cell is
# one line with one marker, so a mutation has a single site and a reviewer can
# read the table off the code. `## BL-104:`'s scoring inversions are what an
# `if/elif` with no `else` does to a decision like this one.
#
# THE TWO NOT-SCANNED STATUSES ARE NOT ONE PATH, and this is the mistake the
# design names explicitly (§6.1a). They share an ORGANIZATIONAL arm — both stop
# with no escape — and differ at PERSONAL: `scan-failed` carries on with no
# acknowledgement demanded (Karl, 2026-08-31: treat it "as if it ran"), while
# `tool-unavailable` stops until an acceptance is recorded. Folding them
# together passes four of the five status cases and fails only the one written
# to catch it.

# ── The report the decision is allowed to read (§6.2b) ──────────────────────
# WP10b/1's `_adopt_secrets_scan_own` stamps `scannedBy: "adoption"` and
# `rulesSource: "framework"` onto the section it produces. Scout's own section
# carries neither. Requiring both here is what stops the decision being made on
# a survey's section or on a `--scan-report` somebody handed in — the three
# inputs §6.2b opens by naming as untrustworthy.
#
# THIS IS A REFUSAL, NOT A DEGRADATION. A stop that cannot tell whose scan it
# is reading has no basis to proceed, and proceeding would be the silent
# failure this package exists to remove.
_adopt_secrets_own_report() {                      # BL-242-SECRETS-OWN-REPORT
  local report="$1" by src
  [ -f "$report" ] || return 1
  by="$(adopt_report_read "$report" '.secrets.scannedBy // ""')"
  src="$(adopt_report_read "$report" '.secrets.rulesSource // ""')"
  [ "$by" = "adoption" ] && [ "$src" = "framework" ]
}

# ── Printing findings, redacted, from the projected section ─────────────────
# The findings this reads were built by Scout's field allowlist
# (`SCOUT-SECRETS-ALLOWLIST`), so there is no secret value in the schema to
# forget to strip. This prints rule, file and line and nothing else — the same
# three facts the archive scan's projection prints, for the same reason.
_adopt_secrets_print_findings() {
  local report="$1" n
  n="$(adopt_int "$(adopt_report_read "$report" '.secrets.findingCount // 0')")"
  [ "$n" -gt 0 ] || return 0
  adopt_note "What the scan found — the value itself is never printed:"
  adopt_report_read "$report" \
    '.secrets.findings[]? | "     \(.ruleId // "?")  \(.file // "?"):\(.startLine // "?")"' \
    | while IFS= read -r line; do [ -n "$line" ] && adopt_say "$line"; done
  return 0
}

# ── The unshallow remedy, spelled once (§6.1a) ──────────────────────────────
# The same two commands four shipped operator-facing sites already print. One
# spelling so a reviewer can compare them and a mutation has one site.
_adopt_secrets_unshallow_remedy() {                # BL-242-SECRETS-UNSHALLOW
  adopt_note "  git remote set-branches origin '*' && git fetch --unshallow"
  adopt_note "  then run Scout again, and adopt once the scan can read the whole history."
}

# ─────────────────────────────────────────────────────────────────────────────
# adopt_secrets_decide REPORT — §6.1's table. 0 to proceed, 1 to stop.
#
# Reads `ADOPT_DEPLOYMENT` (step 1's answer, §6.5 — never the manifest, which
# is not written until step 7) and `ADOPT_DISPOSITIONS_FILE` — TODAY that is
# the `--dispositions` flag or empty, and nothing more. §6.3 also specifies a
# fallback to the adoptee's own `.claude/adoption/secrets-dispositions.json`
# and an interactive prompt; NEITHER IS BUILT, and this comment said otherwise
# until review measured it. (Do not quote a grep count here: an earlier draft
# said `grep -rn secrets-dispositions scripts/` finds ONE hit, and the sentence
# saying so became the second and third.)
#
# EVERY STOP IS A BLOCK, NOT A REFUSAL. `docs/messaging-standard.md` draws the
# line: a refusal is "the tool would not begin", a block is "a named check ran
# and you did not pass it". This is a named check that ran. `adopt_block`
# (WP9d, `# BL-242-BLOCK-LABEL`) is how that label is forced regardless of what
# is on disk.
adopt_secrets_decide() {
  local report="$1"
  local tier="${ADOPT_DEPLOYMENT:-}" status count disp
  disp="${ADOPT_DISPOSITIONS_FILE:-}"

  if [ "$tier" != "organizational" ] && [ "$tier" != "personal" ]; then
    adopt_block "the secrets check cannot run: this run has no deployment tier"
    adopt_note "  The tier is step 1's answer and every row of §6.1's table keys on it."
    return 1
  fi

  if ! _adopt_secrets_own_report "$report"; then
    adopt_block "the secrets check was handed a report it did not produce"
    adopt_note "  This decision is made on a scan adoption ran itself, over a copy of your"
    adopt_note "  history, under the framework's own rules — never on a report supplied to it."
    return 1
  fi

  status="$(adopt_report_read "$report" '.secrets.status // ""')"
  count="$(adopt_int "$(adopt_report_read "$report" '.secrets.findingCount // 0')")"

  case "$tier:$status" in

    # ── CLEAN — the only row where the tiers agree ──────────────────────────
    organizational:scanned|personal:scanned)
      if [ "$count" -eq 0 ]; then                  # BL-242-SECRETS-CLEAN
        adopt_note "The secrets scan read this project's history and found nothing."
        return 0
      fi
      # findings > 0 falls through to the per-tier arms below
      case "$tier" in
        organizational)                            # BL-242-SECRETS-ORG-FINDINGS
          _adopt_secrets_print_findings "$report"
          if adopt_dispositions_satisfy "$report" "$disp" findings; then
            adopt_note "Every finding carries a recorded disposition; adoption continues."
            return 0
          fi
          adopt_block "this project's history carries $count credential finding(s) with no recorded disposition"
          adopt_note "  An organizational adoption does not proceed past an undispositioned finding."
          adopt_note "  Record one per finding — rotated, false alarm, or accepted risk, each with a"
          adopt_note "  name and a reason — and pass the file with --dispositions."
          return 1 ;;
        *)                                         # BL-242-SECRETS-PERSONAL-FINDINGS
          _adopt_secrets_print_findings "$report"
          # THE ADOPTION RECORD EXISTS NOW (WP7/1), AND THIS ARM SAID OTHERWISE
          # FOR ONE COMMIT. The comment here used to explain why it made no
          # claim about the record — because the record was not built — and
          # ended "keep this transcript". WP7/1 built it and did not revisit
          # this arm, so a personal-tier adoption with findings printed BOTH
          # "the Adoption Record ... is not built yet" and, sixty lines later,
          # "The Adoption Record is in APPROVAL_LOG.md". Two contradictory
          # sentences in one run is the exact shape `# BL-225-REFUSE-HONEST`
          # exists to stop, quoted by the comment that was producing it.
          adopt_note "These are REAL findings in your history. Adoption continues because this is a"
          adopt_note "personal project. They are printed here, and they are recorded permanently in"
          adopt_note "the Adoption Record at the end of APPROVAL_LOG.md — by rule, file and line and"
          adopt_note "fingerprint, never the matched value."
          adopt_note "Rotate anything still live: a history rewrite does not un-leak what was fetched."
          return 0 ;;
      esac ;;

    # ── SCAN-FAILED — org stops with no escape; personal carries on ─────────
    organizational:scan-failed)                    # BL-242-SECRETS-ORG-FAILED
      adopt_block "the secrets scan did not complete, so nothing is known about this history"
      adopt_note "  A scan that broke is not a scan that found nothing. An organizational"
      adopt_note "  adoption requires a successful scan — there is no acknowledgement for this."
      adopt_note "  Fix the scanner and run adoption again; nothing has been written."
      return 1 ;;
    personal:scan-failed)                          # BL-242-SECRETS-PERSONAL-FAILED
      # NO FINDINGS LIST HERE, AND THAT IS THE POINT. Rendering an empty list
      # would say "0 findings" over a scan that never produced one — a clean
      # bill of health issued by something that did not happen.
      adopt_note "The secrets scan FAILED. NOTHING is known about credentials in this project's"
      adopt_note "history — this is not a clean result, it is the absence of one."
      adopt_note "Adoption continues because this is a personal project. Scan again when you can."
      return 0 ;;

    # ── TOOL-UNAVAILABLE — org hard refusal; personal escapable on the record
    organizational:tool-unavailable)               # BL-242-SECRETS-ORG-UNAVAILABLE
      adopt_block "no secrets scanner was available, so nothing was scanned"
      adopt_note "  An organizational adoption does not proceed on an unscanned history, and"
      adopt_note "  there is no acknowledgement that lifts this. Install gitleaks and re-run."
      return 1 ;;
    personal:tool-unavailable)                     # BL-242-SECRETS-PERSONAL-UNAVAILABLE
      if adopt_dispositions_satisfy "$report" "$disp" tool-unavailable; then
        adopt_note "No scanner was available and you have accepted that on the record."
        adopt_note "Nothing is known about credentials in this project's history."
        return 0
      fi
      adopt_block "no secrets scanner was available, so nothing was scanned"
      adopt_note "  Adoption can continue on a personal project if you accept that on the"
      adopt_note "  record — a name, a reason and a date, which adoption stores and commits."
      adopt_note "  Install gitleaks and re-run, or supply that acceptance with --dispositions."
      return 1 ;;

    # ── SCANNED-PARTIAL — ruled 2026-09-16 (§6.1a) ──────────────────────────
    organizational:scanned-partial)                # BL-242-SECRETS-ORG-PARTIAL
      _adopt_secrets_print_findings "$report"
      adopt_block "the scan could only read part of this project's history (a shallow clone)"
      adopt_note "  A count of zero here means zero in the commits present. It is not a"
      adopt_note "  statement about this project's history, and a credential that was"
      adopt_note "  committed and later removed lives precisely in the part it could not read."
      adopt_note "  There is no acknowledgement for this at an organizational tier. Unshallow:"
      _adopt_secrets_unshallow_remedy
      return 1 ;;
    personal:scanned-partial)                      # BL-242-SECRETS-PERSONAL-PARTIAL
      _adopt_secrets_print_findings "$report"
      # REQUIRED EVEN AT ZERO FINDINGS. The status is a statement about SCOPE,
      # not about what was found, so "skip the acknowledgement when the count
      # is 0" would silently accept the one case the status exists for.
      if adopt_dispositions_satisfy "$report" "$disp" scanned-partial; then
        adopt_note "The scan read part of this history and you have accepted that on the record."
        return 0
      fi
      adopt_block "the scan could only read part of this project's history (a shallow clone)"
      adopt_note "  Adoption can continue on a personal project if you accept that on the"
      adopt_note "  record. Or unshallow and scan the whole history:"
      _adopt_secrets_unshallow_remedy
      return 1 ;;

    # ── An unknown status is a STOP at both tiers ───────────────────────────
    # A status word this table does not know is not a clean one. `## BL-147:`
    # is the standing rule: a check that cannot run must not pass.
    *)                                             # BL-242-SECRETS-UNKNOWN
      adopt_block "the secrets scan reported a status this version does not understand: '${status:-(none)}'"
      adopt_note "  Adoption stops rather than guess what it means."
      return 1 ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────────────
# adopt_dispositions_satisfy REPORT FILE KIND — does FILE lift this stop?
#
# KIND is `findings` (every finding needs its own row) or one of the two
# acknowledgement kinds (`tool-unavailable`, `scanned-partial`, one row).
# Returns 0 only when the file is present, parses, is bound to THIS scan, and
# every row it relies on carries a signer and a reason.
#
# VALIDATION IS NOT A FORMALITY HERE — IT IS THE WHOLE VALUE OF THE RECORD.
# §6.3's record exists so that an escape leaves a trace with a name on it. A
# file accepted without a signer records nothing; a file accepted against a
# DIFFERENT scan records a decision somebody made about other evidence. Both
# would leave the audit trail technically present and substantively empty,
# which is the advisory posture D2 exists to replace.
#
# EVERY FAILURE PATH SAYS WHY. An unexplained "no" on a file the operator just
# wrote is indistinguishable from the feature being broken, and the operator's
# next move is to delete the file and try something else.
adopt_dispositions_satisfy() {
  local report="$1" file="$2" kind="$3"
  local scan_head scan_commits f_head f_commits n_needed

  [ -n "$file" ] || return 1
  if [ ! -f "$file" ]; then
    adopt_note "  (--dispositions names a file that is not there: $file)"
    return 1
  fi
  if ! jq -e 'type == "object"' "$file" >/dev/null 2>&1; then
    adopt_note "  (the dispositions file is not a JSON object; nothing in it can be read)"
    return 1
  fi

  # ── STALENESS: the file is bound to ONE scan (§6.3) ─────────────────────
  # HEAD and the commit count together. A file written against an earlier HEAD
  # describes findings that may no longer exist and may miss ones that now do;
  # a file written against a fuller history describes a different scope.
  scan_head="$(adopt_report_read "$report" '.secrets.head // ""')"
  scan_commits="$(adopt_int "$(adopt_report_read "$report" '.secrets.commitsScanned // 0')")"
  f_head="$(jq -r '.scan.head // ""' "$file" 2>/dev/null)"
  f_commits="$(adopt_int "$(jq -r '.scan.commitsScanned // 0' "$file" 2>/dev/null)")"
  # FAIL CLOSED WHEN THE BINDING CANNOT BE CHECKED. The first cut skipped both
  # arms when the scan's own values were missing — `[ -n "$scan_head" ] &&` and
  # `[ "$scan_commits" -gt 0 ] &&` — which made the whole staleness check
  # conditional on data that, at the time, no producer emitted. A check that
  # silently does nothing when its input is absent is the fail-open shape
  # `## BL-147:` names: a check that cannot run must not pass.
  if [ -z "$scan_head" ]; then
    adopt_note "  (this scan did not record which commit it read, so no acknowledgement can be"
    adopt_note "   bound to it — refusing rather than accepting one that may describe another scan)"
    return 1
  fi
  if [ "$f_head" != "$scan_head" ]; then   # BL-242-DISPOSITIONS-STALE
    adopt_note "  (the dispositions file was written against a different commit — it describes"
    adopt_note "   another scan, so none of it applies here)"
    return 1
  fi
  if [ "$f_commits" -ne "$scan_commits" ]; then
    if [ "$scan_commits" -eq 0 ]; then
      # DO NOT SAY "THIS SCAN'S 0 COMMITS" WHEN NO SCAN RAN. On
      # `tool-unavailable` the producer emits `commitsScanned: null`, which
      # reads here as 0 — and describing a scan that never happened as one that
      # read zero commits is the same false-precision the `personal:scan-failed`
      # arm warns against a few cells up.
      adopt_note "  (the dispositions file names a scan of $f_commits commit(s); this scan"
      adopt_note "   recorded no commit count at all, because no scanner ran. Remove"
      adopt_note "   scan.commitsScanned from the file, or record the acceptance against"
      adopt_note "   a scan that happened.)"
    else
      adopt_note "  (the dispositions file was written against a scan of a different size —"
      adopt_note "   $f_commits commit(s) against this scan's $scan_commits)"
    fi
    return 1
  fi

  case "$kind" in
    findings)
      n_needed="$(adopt_int "$(adopt_report_read "$report" '.secrets.findingCount // 0')")"
      [ "$n_needed" -gt 0 ] || return 0
      # EVERY FINGERPRINT IN THE FILE MUST BE ONE THIS SCAN PRODUCED, and every
      # finding this scan produced must have a row. The first direction refuses
      # a file carried over from elsewhere; the second refuses a partial one.
      local fps_scan fps_file missing alien
      fps_scan="$(adopt_report_read "$report" '.secrets.findings[]?.fingerprint // empty' | LC_ALL=C sort -u)"
      # NO FINGERPRINTS IS NOT "EVERYTHING IS DISPOSITIONED". With findings on
      # the record but no fingerprint to join on, both set differences below are
      # empty and the stop lifts on a file containing zero dispositions —
      # measured. gitleaks always sets `Fingerprint` today, so this is
      # defence in depth; Scout's own `fieldsMissing` machinery exists because
      # that set is not guaranteed across versions.
      # ONE ARM, NOT TWO. The first cut also tested `[ -z "$(… grep -c …)" ]`,
      # which can never be true — `grep -c` always prints a number, `0` on empty
      # input (measured). Dead code in an enforcement predicate reads as a
      # second defence and is not one.
      if [ "$(printf '%s\n' "$fps_scan" | grep -c .)" -eq 0 ]; then
        adopt_note "  (this scan reported $n_needed finding(s) but no fingerprint to join them by,"
        adopt_note "   so no file can disposition them — refusing rather than treating that as done)"
        return 1
      fi
      # THE SELECT ENFORCES §6.3'S WHOLE ROW, not just its presence. Measured
      # against the first cut, which accepted every one of these: `by` and
      # `reason` of pure whitespace; a row with NO `date` while the block it
      # prints says "it needs a name, a reason and a date"; and a
      # `disposition` of `banana-not-a-vocabulary-word`, or absent entirely —
      # which matters forward, because §6.3 says every `accepted-risk` writes
      # an audit row and the write stage would have had nothing to classify.
      fps_file="$(jq -r '
        def trimmed: (. // "") | gsub("^\\s+|\\s+$"; "");
        .dispositions[]?
        | select((.by | trimmed) != ""
             and (.reason | trimmed) != ""
             and (.date | trimmed) != ""
             and ((.disposition // "") | IN("rotated", "false-alarm", "accepted-risk")))
        | .fingerprint // empty' "$file" 2>/dev/null | LC_ALL=C sort -u)"
      alien="$(printf '%s\n' "$fps_file" | grep -v '^$' | LC_ALL=C comm -23 - <(printf '%s\n' "$fps_scan" | grep -v '^$') 2>/dev/null)"
      if [ -n "$alien" ]; then
        adopt_note "  (the dispositions file names finding(s) this scan did not produce — it is"
        adopt_note "   stale, and a stale file is not a disposition of what is here)"
        return 1
      fi
      missing="$(printf '%s\n' "$fps_scan" | grep -v '^$' | LC_ALL=C comm -23 - <(printf '%s\n' "$fps_file" | grep -v '^$') 2>/dev/null)"
      if [ -n "$missing" ]; then
        adopt_note "  (finding(s) with no signed disposition — every row needs a name and a reason)"
        return 1
      fi
      return 0 ;;

    tool-unavailable|scanned-partial)
      # ONE acknowledgement, of the right KIND, signed and reasoned. The kind
      # matters: an acceptance of a missing scanner is not an acceptance of a
      # truncated history, and treating either as the other would let one
      # recorded decision lift a stop it was never about.
      local ok
      ok="$(jq -r --arg k "$kind" '
        def trimmed: (. // "") | gsub("^\\s+|\\s+$"; "");
        [.acknowledgements[]?
         | select((.kind // "") == $k
              and (.by | trimmed) != ""
              and (.reason | trimmed) != ""
              and (.date | trimmed) != "")] | length' "$file" 2>/dev/null)"
      case "$ok" in ''|*[!0-9]*) ok=0 ;; esac
      if [ "$ok" -lt 1 ]; then
        adopt_note "  (no signed acknowledgement of kind '$kind' in the dispositions file — it"
        adopt_note "   needs a name, a reason and a date)"
        return 1
      fi
      return 0 ;;

    *) return 1 ;;
  esac
}

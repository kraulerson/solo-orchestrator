#!/usr/bin/env bash
# scripts/lib/scout/scout-report.sh — the two projections of one scan: §8.2's
# JSON document, and the human Markdown view rendered from the same data.
#
# SPEC: docs/designs/2026-08-02-brownfield-adoption-v1.md §8.2 (the schema is
# normative) and §4.1 (the operator-facing register is written for a
# NON-DEVELOPER: no phase vocabulary, no framework jargon, no "MVP").
#
# M5: sources nothing. See scripts/lib/scout/scout-core.sh's header.
#
# ONE SCAN, TWO PROJECTIONS — the currency system's precedent, where
# plan-staging writes a machine journal-of-record and a human plan from the
# same manifest. Both functions below read the SAME tab-separated files under
# the work directory. Neither re-derives anything, so the two views cannot
# disagree about what was found; if they ever do, it is a rendering bug and not
# a data question.
#
# THE ABSENT SECTIONS ARE DECLARED, NOT MISSING. This build emits all seven of
# §8.2's sections, so `sectionsNotEmitted` is empty — and it is KEPT, empty,
# rather than removed. A consumer written against the WP1 report reads that key
# to tell "not scanned yet" from "scanned and found nothing"; deleting it the
# moment the list went empty would break that reader on the one release where
# the answer finally became "everything was scanned".
#
# WITHIN `secrets` THE SAME DISTINCTION IS CARRIED BY `status`, at finer grain
# and for higher stakes: `scanned` is a positive result, `tool-unavailable`
# means nobody looked, and `scan-failed` means somebody looked and it broke.
# Collapsing any of those into an empty findings array would be a false clean
# bill of health with a credential behind it.

SCOUT_SECTIONS_EMITTED="stack phaseMap reality secrets collisions testsBaseline intakePrefill"
SCOUT_SECTIONS_NOT_EMITTED=""

# _scout_meta WORK KEY — one metadata value staged by the entry script.
_scout_meta() {
  [ -f "$1/$2" ] || { printf ''; return 0; }
  head -1 "$1/$2"
}

# _scout_bool 0|1 — the JSON literal.
_scout_bool() {
  if [ "$1" = "1" ]; then printf 'true'; else printf 'false'; fi
}

# ── The JSON document (§8.2) ────────────────────────────────────────────────

scout_emit_json() {
  local work="$1"
  local TAB first name files conf rung sat ev result how value source
  local rollup_result rollup_pass rollup_total rollup_how
  TAB=$(printf '\t')

  printf '{\n'
  printf '  "schemaVersion": 1,\n'
  printf '  "scannedAt": %s,\n'      "$(scout_json_str "$(_scout_meta "$work" scannedAt)")"
  printf '  "scannerVersion": %s,\n' "$(scout_json_str "$(scout_module_version)")"
  printf '  "repoRoot": %s,\n'       "$(scout_json_str "$(_scout_meta "$work" repoRoot)")"
  printf '  "headCommit": %s,\n'     "$(scout_json_str_or_null "$(_scout_meta "$work" headCommit)")"
  printf '  "sections": %s,\n'          "$(scout_json_array_from_words "$SCOUT_SECTIONS_EMITTED")"
  printf '  "sectionsNotEmitted": %s,\n' "$(scout_json_array_from_words "$SCOUT_SECTIONS_NOT_EMITTED")"

  # ── stack ────────────────────────────────────────────────────────────────
  printf '  "stack": {\n'
  printf '    "languages": ['
  first=1
  while IFS="$TAB" read -r name files conf; do
    [ -n "$name" ] || continue
    [ "$first" -eq 1 ] || printf ', '
    printf '{"name": %s, "files": %s, "confidence": %s}' \
      "$(scout_json_str "$name")" "$files" "$(scout_json_str "$conf")"
    first=0
  done < "$work/lang"
  printf '],\n'
  printf '    "packageManagers": %s,\n' "$(scout_json_array_from_file "$work/pkgmgr")"
  printf '    "buildFiles": %s,\n'      "$(scout_json_array_from_file "$work/buildfiles")"
  value=""; source=""
  if [ -s "$work/testcmd" ]; then
    value=$(cut -f1 < "$work/testcmd")
    source=$(cut -f2 < "$work/testcmd")
  fi
  printf '    "testCommand": {"value": %s, "source": %s},\n' \
    "$(scout_json_str_or_null "$value")" "$(scout_json_str_or_null "$source")"
  printf '    "ciHost": %s\n' "$(scout_json_str_or_null "$(_scout_meta "$work" cihost)")"
  printf '  },\n'

  # ── phaseMap ─────────────────────────────────────────────────────────────
  printf '  "phaseMap": {\n'
  printf '    "suggestedPhase": %s,\n'       "$(_scout_meta "$work" suggested)"
  printf '    "highestSatisfiedRung": %s,\n' "$(_scout_meta "$work" highest)"
  printf '    "rungs": ['
  first=1
  while IFS="$TAB" read -r rung sat ev; do
    [ -n "$rung" ] || continue
    [ "$first" -eq 1 ] || printf ', '
    printf '{"rung": %s, "evidence": %s, "satisfied": %s}' \
      "$rung" "$(scout_json_str "$ev")" "$(_scout_bool "$sat")"
    first=0
  done < "$work/rungs"
  printf '],\n'
  # §8.2, verbatim. It is the design's sentence and it travels with the number.
  printf '    "note": "maximum satisfied rung; the interview may only lower this"\n'
  printf '  },\n'

  # ── reality ──────────────────────────────────────────────────────────────
  printf '  "reality": {\n'
  printf '    "probes": ['
  first=1
  while IFS="$TAB" read -r name result how; do
    [ -n "$name" ] || continue
    [ "$first" -eq 1 ] || printf ', '
    printf '{"name": %s, "result": %s, "how": %s}' \
      "$(scout_json_str "$name")" "$(scout_json_str "$result")" "$(scout_json_str "$how")"
    first=0
  done < "$work/probes"
  printf '],\n'
  rollup_result=""; rollup_pass=0; rollup_total=0; rollup_how=""
  if [ -s "$work/rollup" ]; then
    rollup_result=$(cut -f1 < "$work/rollup")
    rollup_pass=$(cut -f2 < "$work/rollup")
    rollup_total=$(cut -f3 < "$work/rollup")
    rollup_how=$(cut -f4 < "$work/rollup")
  fi
  printf '    "rollup": {"name": "initialization_verified", "result": %s, "passed": %s, "total": %s, "how": %s},\n' \
    "$(scout_json_str "$rollup_result")" "$rollup_pass" "$rollup_total" "$(scout_json_str "$rollup_how")"
  printf '    "omitted": [{"name": "data_model_applied", "why": %s}]\n' \
    "$(scout_json_str "not probeable from the filesystem — whether a data model was applied and a restore was tested is a question only a person can answer, so it is omitted rather than guessed")"
  printf '  },\n'

  # ── secrets (§6.2's projection, §8.2's object) ───────────────────────────
  # EVERY FINDING OBJECT IS PRE-RENDERED BY scout-secrets.sh AND COPIED HERE
  # VERBATIM. This function does not see field names, does not choose which to
  # print, and has no access to anything the allowlist refused — so no bug in
  # this renderer can leak a value it was never handed. That is the point of
  # doing the projection at extraction time rather than at print time.
  _scout_emit_secrets "$work"

  # ── collisions (§1.2's inventory, §7.1's buckets) ────────────────────────
  _scout_emit_collisions "$work"

  # ── testsBaseline (§8.2) ─────────────────────────────────────────────────
  _scout_emit_tests "$work"

  # ── intakePrefill (§8.3) ─────────────────────────────────────────────────
  _scout_emit_prefill "$work"

  printf '}\n'
  return 0
}

# _scout_emit_secrets WORK — the `secrets` object, trailing comma included.
_scout_emit_secrets() {
  local work="$1" status cfg count first line
  status=$(_scout_meta "$work" secstatus)
  cfg=$(_scout_meta "$work" secconfig)
  count=$(_scout_meta "$work" seccount)

  printf '  "secrets": {\n'
  printf '    "tool": %s,\n'        "$(scout_json_str "$(_scout_meta "$work" sectool)")"
  printf '    "toolVersion": %s,\n' "$(scout_json_str_or_null "$(_scout_meta "$work" secversion)")"
  printf '    "status": %s,\n'      "$(scout_json_str "$status")"
  printf '    "scope": %s,\n'       "$(scout_json_str_or_null "$(_scout_meta "$work" secscope)")"
  printf '    "configFile": %s,\n'  "$(scout_json_str_or_null "$cfg")"
  if [ -n "$cfg" ]; then
    printf '    "configNote": %s,\n' \
      "$(scout_json_str "This project ships its own gitleaks configuration and the scan honoured it, which is correct — it is their configuration. It is disclosed because a count produced under rules written by the thing being audited is a different claim from a clean scan: an allowlist rule in that file can take a real finding to zero.")"
  else
    printf '    "configNote": null,\n'
  fi
  printf '    "redaction": %s,\n' \
    "$(scout_json_str "field allowlist projection — each finding is built from RuleID, File, Commit, Fingerprint, StartLine, Date and Description, and the tool's report is never passed through. There is no secret field in this schema to forget to strip, and the commit message (which the scanner does NOT redact) is refused.")"
  printf '    "fieldsMissing": %s,\n' "$(scout_json_array_from_file "$work/secmissing")"
  printf '    "note": %s,\n' "$(scout_json_str "$(_scout_meta "$work" secnote)")"
  if [ "$status" = "scanned" ]; then
    printf '    "remediation": null,\n'
  else
    printf '    "remediation": %s,\n' "$(scout_json_str "$(_scout_meta "$work" secnote)")"
  fi
  # §6.4: the instructions are PRINTED, never executed. Scout runs no rewrite,
  # and the sentence that matters most is that a rewrite does not un-leak
  # anything already fetched — so rotation comes first, always.
  if [ "$status" = "scanned" ] && [ -n "$count" ] && [ "$count" != "0" ]; then
    printf '    "historyRewrite": %s,\n' \
      "$(scout_json_str "ROTATE FIRST. A history rewrite (git filter-repo, or BFG) followed by a force-push and a re-clone by every collaborator removes the value from the repository, but it does NOT un-leak anything already cloned or fetched by anyone. Rotation at the source of truth is the fix; the rewrite is housekeeping afterwards. Scout prints this and runs none of it.")"
  else
    printf '    "historyRewrite": null,\n'
  fi
  if [ "$status" = "scanned" ]; then
    printf '    "findingCount": %s,\n' "${count:-0}"
    printf '    "findings": ['
    first=1
    if [ -s "$work/secjson" ]; then
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        [ "$first" -eq 1 ] || printf ', '
        printf '%s' "$line"
        first=0
      done < "$work/secjson"
    fi
    printf ']\n'
  else
    # NOT `[]`. An empty array reads as "scanned and clean" to every consumer
    # that does not also check status, and that misreading is the entire
    # silent-success defect class this section is written against.
    printf '    "findingCount": null,\n'
    printf '    "findings": null\n'
  fi
  printf '  },\n'
  return 0
}

# _scout_emit_collisions WORK — the `collisions` object, trailing comma.
_scout_emit_collisions() {
  local work="$1" TAB first path class bucket desc note findings
  local rule dpath dline dwhy
  TAB=$(printf '\t')

  printf '  "collisions": {\n'
  printf '    "entries": ['
  first=1
  if [ -s "$work/colentries" ]; then
    while IFS="$TAB" read -r path class bucket desc note findings; do
      [ -n "$path" ] || continue
      desc=$(_scout_col_unblank "$desc")
      note=$(_scout_col_unblank "$note")
      findings=$(_scout_col_unblank "$findings")
      [ "$first" -eq 1 ] || printf ', '
      printf '{"path": %s, "class": %s, "bucket": %s, "description": %s, "note": %s, "findings": %s}' \
        "$(scout_json_str "$path")" "$(scout_json_str "$class")" "$(scout_json_str "$bucket")" \
        "$(scout_json_str_or_null "$desc")" "$(scout_json_str_or_null "$note")" \
        "$(scout_json_array_from_words "$(printf '%s' "$findings" | tr ',' ' ')")"
      first=0
    done < "$work/colentries"
  fi
  printf '],\n'
  # THE DETAIL ROWS CARRY A LINE NUMBER AND NEVER THE LINE. A workflow step can
  # hold a credential as easily as a hook can; quoting the matched text to be
  # helpful would reintroduce §6.2's leak in a section that does not mention it.
  printf '    "findingDetail": ['
  first=1
  if [ -s "$work/coldetail" ]; then
    while IFS="$TAB" read -r rule dpath dline dwhy; do
      [ -n "$rule" ] || continue
      [ "$first" -eq 1 ] || printf ', '
      printf '{"rule": %s, "path": %s, "line": %s, "why": %s}' \
        "$(scout_json_str "$rule")" "$(scout_json_str "$dpath")" "${dline:-0}" \
        "$(scout_json_str "$dwhy")"
      first=0
    done < "$work/coldetail"
  fi
  printf '],\n'
  printf '    "note": %s\n' \
    "$(scout_json_str "Report-only. Scout changed none of these files and adoption would not change the audit-only ones at all. Findings name the rule, the file and the line; the matched text is deliberately not quoted.")"
  printf '  },\n'
  return 0
}

# _scout_emit_tests WORK — the `testsBaseline` object, trailing comma.
_scout_emit_tests() {
  local work="$1" ran rc dur value source
  ran=$(_scout_meta "$work" tbran)
  rc=$(_scout_meta "$work" tbrc)
  dur=$(_scout_meta "$work" tbdur)
  value=""; source=""
  if [ -s "$work/testcmd" ]; then
    value=$(cut -f1 < "$work/testcmd")
    source=$(cut -f2 < "$work/testcmd")
  fi

  printf '  "testsBaseline": {\n'
  printf '    "testCommand": {"value": %s, "source": %s},\n' \
    "$(scout_json_str_or_null "$value")" "$(scout_json_str_or_null "$source")"
  printf '    "commandRan": %s,\n' "$(_scout_bool "$ran")"
  printf '    "reason": %s,\n'     "$(scout_json_str "$(_scout_meta "$work" tbreason)")"
  if [ "$ran" = "1" ] && [ -n "$rc" ]; then
    printf '    "exitCode": %s,\n' "$rc"
  else
    printf '    "exitCode": null,\n'
  fi
  if [ "$ran" = "1" ] && [ -n "$dur" ]; then
    printf '    "durationSeconds": %s,\n' "$dur"
  else
    printf '    "durationSeconds": null,\n'
  fi
  printf '    "timedOut": %s,\n' "$(_scout_bool "$(_scout_meta "$work" tbtimeout)")"
  printf '    "totalSourceFiles": %s,\n'    "$(_scout_meta "$work" tbtotal)"
  printf '    "testFiles": %s,\n'           "$(_scout_meta "$work" tbtests)"
  printf '    "untestedSourceFiles": %s,\n' "$(_scout_meta "$work" tbuntested)"
  printf '    "classifier": %s,\n' "$(scout_json_str "tdd-classify parity (extracted, not sourced)")"
  printf '    "classifierParity": {"carried": %s, "simplified": %s},\n' \
    "$(scout_json_array_from_file "$work/tbcarried")" \
    "$(scout_json_array_from_file "$work/tbsimplified")"
  printf '    "untestedMethod": %s\n' "$(scout_json_str "$(scout_testsbaseline_method)")"
  printf '  },\n'
  return 0
}

# _scout_emit_prefill WORK — the `intakePrefill` object, NO trailing comma
# (it is the last section in the document).
_scout_emit_prefill() {
  local work="$1" TAB first id runner title kind field value source
  TAB=$(printf '\t')

  printf '  "intakePrefill": {\n'
  printf '    "note": %s,\n' \
    "$(scout_json_str "One row per intake section. A scan-derived row carries a value AND where it came from, so the operator can check it rather than take it on trust; a judgment or non-skippable row carries null, because a guessed answer is worse than an absent one — it gets confirmed away.")"
  printf '    "sections": ['
  first=1
  if [ -s "$work/prefill" ]; then
    while IFS="$TAB" read -r id runner title kind field value source; do
      [ -n "$id" ] || continue
      [ "$first" -eq 1 ] || printf ', '
      printf '{"id": %s, "runner": %s, "title": %s, "kind": %s, "field": %s, "value": %s, "source": %s}' \
        "$(scout_json_str "$id")" "$(scout_json_str "$runner")" "$(scout_json_str "$title")" \
        "$(scout_json_str "$kind")" "$(scout_json_str "$field")" \
        "$(scout_json_str_or_null "$value")" "$(scout_json_str_or_null "$source")"
      first=0
    done < "$work/prefill"
  fi
  printf ']\n'
  printf '  }\n'
  return 0
}

# ── The human view (§4.1's register) ────────────────────────────────────────

# _scout_phase_sentence N — what the placement means, without saying "phase".
_scout_phase_sentence() {
  case "$1" in
    0) printf 'We could not find a written description of what this project is for.\n' ;;
    1) printf 'There is a written description of what this project is for.\n' ;;
    2) printf 'The project is described and its technical shape is written down.\n' ;;
    3) printf 'The project is described, its shape is written down, and it has tests that can actually be run.\n' ;;
    4) printf 'The project is described, its shape is written down, it has runnable tests, and there is a way to get it out the door.\n' ;;
    *) printf 'Placement could not be determined.\n' ;;
  esac
}

scout_emit_markdown() {
  local work="$1"
  local TAB name files conf rung sat ev result how value source mark
  local suggested highest rollup_result rollup_pass rollup_total rollup_how
  TAB=$(printf '\t')

  suggested=$(_scout_meta "$work" suggested)
  highest=$(_scout_meta "$work" highest)

  printf '# Scout report\n\n'
  printf 'A read-only look at **%s**. Scout changed nothing — it only read.\n\n' \
    "$(_scout_meta "$work" repoRoot)"
  printf '| | |\n|---|---|\n'
  printf '| Looked at | %s |\n' "$(_scout_meta "$work" scannedAt)"
  printf '| Scout version | %s |\n' "$(scout_module_version)"
  printf '| Latest commit | %s |\n' "$( [ -n "$(_scout_meta "$work" headCommit)" ] && _scout_meta "$work" headCommit || printf 'not a git repository' )"
  printf '\n'
  if [ -n "$SCOUT_SECTIONS_NOT_EMITTED" ]; then
    printf 'This version reports on **%s**. It does *not* yet report on %s — those are not "clean", they are **not looked at yet**.\n\n' \
      "$(printf '%s' "$SCOUT_SECTIONS_EMITTED" | sed -e 's/ /, /g')" \
      "$(printf '%s' "$SCOUT_SECTIONS_NOT_EMITTED" | sed -e 's/ /, /g')"
  else
    printf 'This version looked at everything it knows how to look at: **%s**.\n\n' \
      "$(printf '%s' "$SCOUT_SECTIONS_EMITTED" | sed -e 's/ /, /g')"
  fi

  # ── What it is built with ────────────────────────────────────────────────
  printf -- '---\n\n## What this project is built with\n\n'
  if [ -s "$work/lang" ]; then
    printf '| Language | Files | How sure we are |\n|---|---|---|\n'
    while IFS="$TAB" read -r name files conf; do
      [ -n "$name" ] || continue
      printf '| %s | %s | %s |\n' "$name" "$files" "$conf"
    done < "$work/lang"
  else
    printf 'No source files in a language Scout recognises.\n'
  fi
  printf '\n'
  printf -- '- **Package managers in use:** %s\n' \
    "$( [ -s "$work/pkgmgr" ] && tr '\n' ' ' < "$work/pkgmgr" || printf 'none found' )"
  printf -- '- **Build / manifest files:** %s\n' \
    "$( [ -s "$work/buildfiles" ] && tr '\n' ' ' < "$work/buildfiles" || printf 'none found' )"
  value=""; source=""
  if [ -s "$work/testcmd" ]; then
    value=$(cut -f1 < "$work/testcmd"); source=$(cut -f2 < "$work/testcmd")
  fi
  if [ -n "$value" ]; then
    printf -- '- **How the tests are run:** `%s` (found in %s)\n' "$value" "$source"
  else
    printf -- '- **How the tests are run:** Scout could not find a test command.\n'
  fi
  printf -- '- **Where the automated checks live:** %s\n\n' \
    "$( [ -n "$(_scout_meta "$work" cihost)" ] && _scout_meta "$work" cihost || printf 'no automated checks found' )"

  # ── How far along ────────────────────────────────────────────────────────
  printf -- '---\n\n## How far along this project looks\n\n'
  printf '**Suggested starting point: %s.** %s\n' "$suggested" "$(_scout_phase_sentence "$suggested")"
  printf '\nThis is a ceiling, not a verdict: %s\n\n' \
    "maximum satisfied rung; the interview may only lower this"
  if [ "$highest" != "$suggested" ]; then
    printf 'Worth knowing: this project has evidence for step %s, but step %s is missing, so the count stops at %s. Having the later thing without the earlier one is normal in a project that grew organically — it is not a problem, it is just something the interview should ask about.\n\n' \
      "$highest" "$(( suggested + 1 ))" "$suggested"
  fi
  printf '| Step | Found? | What we looked at |\n|---|---|---|\n'
  while IFS="$TAB" read -r rung sat ev; do
    [ -n "$rung" ] || continue
    if [ "$sat" = "1" ]; then mark="yes"; else mark="no"; fi
    printf '| %s | %s | %s |\n' "$rung" "$mark" "$ev"
  done < "$work/rungs"
  printf '\n'

  # ── What is already set up ───────────────────────────────────────────────
  printf -- '---\n\n## What is already set up\n\n'
  printf '| Check | Result | How Scout decided | Internal name |\n|---|---|---|---|\n'
  while IFS="$TAB" read -r name result how; do
    [ -n "$name" ] || continue
    printf '| %s | **%s** | %s | `%s` |\n' \
      "$(printf '%s' "$name" | tr '_' ' ')" "$result" "$how" "$name"
  done < "$work/probes"
  printf '\n'
  rollup_result=""; rollup_pass=0; rollup_total=0; rollup_how=""
  if [ -s "$work/rollup" ]; then
    rollup_result=$(cut -f1 < "$work/rollup")
    rollup_pass=$(cut -f2 < "$work/rollup")
    rollup_total=$(cut -f3 < "$work/rollup")
    rollup_how=$(cut -f4 < "$work/rollup")
  fi
  printf '**Overall: %s** — %s. (%s of %s passed; internal name `initialization_verified`.)\n\n' \
    "$rollup_result" "$rollup_how" "$rollup_pass" "$rollup_total"
  printf 'One check is deliberately left unanswered. Scout will not sign in to your git host or use your credentials, so it cannot see whether your main branch is protected. "Unknown" means exactly that — not "no".\n\n'
  printf 'One more check is missing on purpose: whether a data model was applied and a restore was tested. Nothing on disk can answer that, so Scout does not guess.\n\n'

  _scout_md_secrets    "$work"
  _scout_md_collisions "$work"
  _scout_md_tests      "$work"
  _scout_md_prefill    "$work"
  return 0
}

# _scout_md_unescape BODY — a JSON string body rendered for a person.
#
# The projection keeps values in their original JSON escaping so the machine
# view can re-emit them without a lossy round trip. The human view undoes the
# two escapes that actually occur in a path or a rule name. `\uXXXX` is left
# visible rather than decoded: a mangled character in a filename is a cosmetic
# problem, and a hand-rolled unicode decoder is a real one.
_scout_md_unescape() {
  printf '%s' "$1" | sed -e 's/\\"/"/g' -e 's/\\\\/\\/g' -e 's|\\/|/|g'
}

# _scout_secfield WORK IDX FIELD — one projected value, for display.
_scout_secfield() {
  local v
  v=$(awk -F'\t' -v i="$2" -v k="$3" '$1==i && $2==k { sub(/^[^\t]*\t[^\t]*\t[^\t]*\t/, ""); print; exit }' \
        "$1/secfields" 2>/dev/null)
  _scout_md_unescape "$v"
}

# _scout_md_secrets WORK — §4.1's register: no jargon, and the consequence
# stated plainly. §6.3 (a disposition per finding) and §6.4 (the rewrite is
# printed, never run) both live here, because this is the view a person reads.
_scout_md_secrets() {
  local work="$1" status count idx cfg
  status=$(_scout_meta "$work" secstatus)
  count=$(_scout_meta "$work" seccount)
  cfg=$(_scout_meta "$work" secconfig)

  printf -- '---\n\n'
  printf "## Secrets in this project's history\n\n"
  case "$status" in
    tool-unavailable)
      printf '**Nobody looked.** %s\n\n' "$(_scout_meta "$work" secnote)"
      return 0
      ;;
    scan-failed)
      printf '**The scan did not finish.** %s\n\n' "$(_scout_meta "$work" secnote)"
      return 0
      ;;
  esac

  if [ -n "$cfg" ]; then
    printf 'Note: this project has its own `%s`, and the scan obeyed it. If that file allows a pattern, anything matching it was not counted.\n\n' "$cfg"
  fi

  if [ -z "$count" ] || [ "$count" = "0" ]; then
    printf 'Scout scanned %s and found **nothing**. That is a real result, not a blank: the scanner ran and reported no matches.\n\n' \
      "$( [ "$(_scout_meta "$work" secscope)" = "full-history" ] && printf 'every commit in this project, not just the current files' || printf 'the current files (this is not a git repository, so there is no history to read)' )"
    return 0
  fi

  printf '  ┌────────────────────────────────────────────────────────────────┐\n'
  # The box interior is 64 columns. This line is 2 + 40 + 1 of literal text
  # plus the pad plus one trailing space, so the pad is 20 — measured, because
  # the border characters are three BYTES and one COLUMN each and eyeballing
  # the alignment of a mixed-width box is how it ends up crooked.
  printf '  │  SECRETS FOUND IN YOUR PROJECT'"'"'S HISTORY: %-20s │\n' "$count"
  printf '  │                                                                │\n'
  printf '  │  Your history is visible to anyone who has ever cloned this    │\n'
  printf '  │  project. Deleting the line does not help — the old commit     │\n'
  printf '  │  still contains it.                                            │\n'
  printf '  │                                                                │\n'
  printf '  │  ROTATION, NOT DELETION, IS THE FIX. Change the credential     │\n'
  printf '  │  where it lives (AWS, your database, the API provider) and     │\n'
  printf '  │  the copy in this history stops being worth anything.          │\n'
  printf '  └────────────────────────────────────────────────────────────────┘\n\n'

  printf 'The value itself is **not printed below and is not stored anywhere in this report** — only where to find it.\n\n'
  # The RULE ID, not the Description. Both are allowlisted and both are in the
  # JSON, but gitleaks' `Description` is a full sentence of risk prose — three
  # of them in a table column make the table unreadable, and the id
  # (`aws-access-token`) is also the string an operator greps for.
  printf '| What matched | Where | Line | Commit | When |\n|---|---|---|---|---|\n'
  idx=1
  while [ "$idx" -le "$count" ]; do
    printf '| `%s` | `%s` | %s | `%s` | %s |\n' \
      "$(_scout_secfield "$work" "$idx" RuleID)" \
      "$(_scout_secfield "$work" "$idx" File)" \
      "$(_scout_secfield "$work" "$idx" StartLine)" \
      "$(printf '%s' "$(_scout_secfield "$work" "$idx" Commit)" | cut -c1-10)" \
      "$(_scout_secfield "$work" "$idx" Date)"
    idx=$((idx + 1))
  done
  printf '\n'
  printf 'Each one needs an answer recorded against it: **rotated** (with the date), **false alarm** (with a reason — the rule name is not a reason), or **accepted risk** (with the name of the person accepting it).\n\n'
  printf 'Rewriting the history is possible (`git filter-repo` or BFG, a force-push, and every collaborator re-clones) but it **does not un-leak anything already fetched**, so rotation comes first. Scout does not run any of that.\n\n'
  return 0
}

# _scout_md_bucket_phrase BUCKET — §7.1's bucket, said without the vocabulary.
#
# A FUNCTION AND NOT AN INLINE `case`, for a measured reason: bash 3.2 — the
# floor this repository targets — cannot parse a multi-line `case` inside a
# `$( )` substitution used as a printf argument, and fails it at RUNTIME with
# `syntax error near unexpected token'. The report still rendered (the
# substitution simply produced nothing), so the only thing that caught it was
# the suite's stderr-must-be-empty case. That is what that case is for.
_scout_md_bucket_phrase() {
  case "$1" in
    archive-and-replace) printf 'kept a copy, then replaced' ;;
    marker-composed)     printf 'left alone; the framework adds to it' ;;
    audit-only)          printf 'not touched at all' ;;
    keep-theirs)         printf 'yours stays' ;;
    *)                   printf '%s' "$1" ;;
  esac
}

# _scout_md_collisions WORK
_scout_md_collisions() {
  local work="$1" TAB path class bucket desc note findings n
  TAB=$(printf '\t')
  printf -- '---\n\n'
  printf '## What would collide with the framework\n\n'
  n=$(grep -c '' "$work/colentries" 2>/dev/null)
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  if [ "$n" -eq 0 ]; then
    printf 'Nothing. This project has none of the files the framework writes, so there is nothing to move out of the way.\n\n'
    return 0
  fi
  printf 'Scout found **%s** things here that the framework also has an opinion about. It moved none of them.\n\n' "$n"
  printf '| What you have | What would happen to it | Why |\n|---|---|---|\n'
  while IFS="$TAB" read -r path class bucket desc note findings; do
    [ -n "$path" ] || continue
    desc=$(_scout_col_unblank "$desc")
    note=$(_scout_col_unblank "$note")
    printf '| `%s` | %s | %s |\n' "$path" "$(_scout_md_bucket_phrase "$bucket")" "$note"
    if [ -n "$desc" ]; then
      printf '| | *(what it does today)* | %s |\n' "$desc"
    fi
  done < "$work/colentries"
  printf '\n'
  if [ -s "$work/coldetail" ]; then
    printf 'Some of your automated checks do things that would work against the safety rails. **Nothing was changed** — this is for you to decide:\n\n'
    printf '| File | Line | Concern |\n|---|---|---|\n'
    while IFS="$TAB" read -r r p l w; do
      [ -n "$r" ] || continue
      printf '| `%s` | %s | %s |\n' "$p" "$l" "$w"
    done < "$work/coldetail"
    printf '\n'
  fi
  return 0
}

# _scout_md_tests WORK
_scout_md_tests() {
  local work="$1" ran total unt
  printf -- '---\n\n'
  printf '## What the tests do today\n\n'
  ran=$(_scout_meta "$work" tbran)
  total=$(_scout_meta "$work" tbtotal)
  unt=$(_scout_meta "$work" tbuntested)
  if [ "$ran" = "1" ]; then
    if [ "$(_scout_meta "$work" tbtimeout)" = "1" ]; then
      printf 'Scout ran your test command and **stopped it** after it went on too long. %s\n\n' \
        "$(_scout_meta "$work" tbreason)"
    else
      printf 'Scout ran your test command once. It finished with exit code **%s** after %s second(s). Zero means they passed.\n\n' \
        "$(_scout_meta "$work" tbrc)" "$(_scout_meta "$work" tbdur)"
    fi
  else
    printf '**Scout did not run anything.** %s\n\n' "$(_scout_meta "$work" tbreason)"
  fi
  printf -- '- **Source files:** %s\n' "$total"
  printf -- '- **Test files:** %s\n' "$(_scout_meta "$work" tbtests)"
  printf -- '- **Source files with no test that names them:** %s\n\n' "$unt"
  printf 'That last number is a rough count, not a coverage figure. %s\n\n' "$(scout_testsbaseline_method)"
  return 0
}

# _scout_md_prefill WORK
_scout_md_prefill() {
  local work="$1" TAB id runner title kind field value source
  TAB=$(printf '\t')
  printf -- '---\n\n'
  printf '## What the interview can skip\n\n'
  printf 'The setup interview asks about fifteen things. Scout already knows the answer to some of them from your files, and it will show you each one with where it got it so you can correct it. The rest are decisions only you can make, and it will not guess at those.\n\n'
  printf '| Topic | Scout already knows | Where it got that |\n|---|---|---|\n'
  while IFS="$TAB" read -r id runner title kind field value source; do
    [ -n "$id" ] || continue
    if [ "$kind" = "scan-derived" ]; then
      printf '| %s | `%s` | %s |\n' "$title" "$value" "$source"
    elif [ "$kind" = "non-skippable" ]; then
      printf '| %s | **you must answer this one** | there is no way to work it out from your files, and the project cannot move forward without it |\n' "$title"
    else
      printf '| %s | — | this is a judgement call, so Scout leaves it to you |\n' "$title"
    fi
  done < "$work/prefill"
  printf '\n'
  return 0
}

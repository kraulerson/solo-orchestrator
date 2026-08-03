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
# THE ABSENT SECTIONS ARE DECLARED, NOT MISSING. This build emits three of
# §8.2's seven sections. `sections` names what is here and `sectionsNotEmitted`
# names what is not, so a consumer can tell "not scanned yet" from "scanned and
# found nothing". For `secrets` that distinction is the whole difference
# between a survey and a false clean bill of health, which is why the absence
# is spelled out in the document rather than left to be inferred from a missing
# key.

SCOUT_SECTIONS_EMITTED="stack phaseMap reality"
SCOUT_SECTIONS_NOT_EMITTED="testsBaseline secrets collisions intakePrefill"

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
  printf '  }\n'
  printf '}\n'
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
  printf 'This version reports on **%s**. It does *not* yet report on %s — those are not "clean", they are **not looked at yet**.\n\n' \
    "$(printf '%s' "$SCOUT_SECTIONS_EMITTED" | sed -e 's/ /, /g')" \
    "$(printf '%s' "$SCOUT_SECTIONS_NOT_EMITTED" | sed -e 's/ /, /g')"

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
  printf 'One more check is missing on purpose: whether a data model was applied and a restore was tested. Nothing on disk can answer that, so Scout does not guess.\n'
  return 0
}

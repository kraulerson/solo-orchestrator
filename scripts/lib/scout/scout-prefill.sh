#!/usr/bin/env bash
# scripts/lib/scout/scout-prefill.sh — §8.2's `intakePrefill` section and
# §8.3's REVERSE INTAKE mapping: one row per intake section, classified.
#
# SPEC: docs/designs/2026-08-02-brownfield-adoption-v1.md §8.3 (scan-derived /
# judgment / data-classification), §8.2 (the schema and the extraction table),
# §10-WP4 (this table is that package's REQUIRED deliverable, enumerated at
# fifteen runners), §4.2 (evidence carries its provenance).
#
# M5: sources nothing. See scripts/lib/scout/scout-core.sh's header.
#
# ─────────────────────────────────────────────────────────────────────────────
# THE ORDINARY INTAKE ASKS A PERSON AND WRITES A DOCUMENT. REVERSE INTAKE
# STARTS FROM THE DOCUMENT THE SCAN ALREADY DERIVED AND ASKS THE PERSON TO
# CONFIRM IT — for the parts that are derivable, and only those.
#
# Three classes, and the boundary between them is the whole point:
#
#   scan-derived    Prefilled and confirmed. Two disclosure lines naming the
#                   value AND ITS PROVENANCE, then keep-it / change-it, with
#                   "change it" falling through to the ordinary question.
#   judgment        Human-mandatory. No prefill, no default, no skip. The
#                   prefill pattern is right for facts the framework recorded
#                   and WRONG for judgments it has never made. A guessed
#                   business context is worse than an empty one, because it
#                   gets confirmed away by a tired operator.
#   non-skippable   No default, no inference, no "confirm" arm at all. This is
#                   a mechanical necessity rather than a policy preference: the
#                   Phase 1->2 ZDR backstop is a hard FAIL, so a project that
#                   reached phase 2 without answering it cannot pass its gate.
#
# ─────────────────────────────────────────────────────────────────────────────
# THE TABLE IS A STATIC DATA BLOCK, AND THAT IS AN M5 CONSEQUENCE, NOT LAZINESS.
#
# Scout must run in a clone that has never had the framework applied to it, so
# it cannot read the wizard at scan time to enumerate its sections. The table
# is therefore transcribed here — which creates exactly one risk, that the
# wizard grows a section and this table does not. The suite closes it: case P1
# derives the runner list from the real scripts/intake-wizard.sh (the SUITE may
# read it; Scout may not) and fails if the two disagree. That is the currency
# canary this file depends on, and it is the reason a row may never be added
# here without running the suite.
#
# NEVER A GUESSED VALUE. A judgment row carries value:null. Not "TBD", not an
# empty string, not a plausible-looking default — null, so that a consumer
# cannot mistake absence for an answer.

# _scout_prefill_table — the §8.3 mapping, as TSV data.
#
#   <id> <runner> <title> <kind> <field> <sourceHint>
#
# WP4-brownfield consumes this. `sourceHint` names the scan field that feeds a
# scan-derived row and is `-` for the rows nothing feeds.
_scout_prefill_table() {
  cat <<'PREFILL'
1	run_section_1	Project Identity	scan-derived	project_name	stack.buildFiles (package.json name) or the project directory
1_repo_setup	run_section_1_repo_setup	Repo Setup	scan-derived	repo_remote_configured	reality.probes remote_repo_created
2	run_section_2	Business Context	judgment	problem_statement	-
3	run_section_3	Constraints	judgment	timeline	-
4	run_section_4	Features & Requirements	judgment	mvp_features	-
5	run_section_5	Data & Integrations (incl. 5.5 Data Classification & ZDR)	non-skippable	data_classification	-
6	run_section_6	Technical Preferences	judgment	competency_matrix	-
7	run_section_7	Revenue Model	judgment	revenue_model	-
8	run_section_8	Governance Pre-Flight	judgment	governance	-
9	run_section_9	Accessibility & UX Constraints	judgment	accessibility	-
10	run_section_10	Distribution & Operations	judgment	uptime	-
11	run_section_11	Known Risks & Concerns	judgment	known_risks	-
11_5	run_section_11_5	Testing & Bug Tracking	scan-derived	test_command	stack.testCommand
12	run_section_12	Tooling Configuration	scan-derived	tooling	stack.packageManagers
13	run_section_13	Agent Initialization Prompt	scan-derived	agent_init_prompt	generated from the completed intake
PREFILL
}

# _scout_json_top_string FILE KEY — the value of a TOP-LEVEL JSON string key.
#
# Depth-aware on purpose: a whole-file grep for `"name"` reads the first
# dependency's name on most real package.json files, and a prefilled project
# name that is silently the name of a transitive dependency is precisely the
# kind of confident wrong answer §4.2 exists to prevent.
_scout_json_top_string() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 0
  awk -v key="$key" '
    function readstr(   body, c) {
      i++
      body = ""
      while (i <= L) {
        c = substr(buf, i, 1)
        if (c == "\\") { body = body substr(buf, i + 1, 1); i += 2; continue }
        if (c == "\"") { i++; return body }
        body = body c; i++
      }
      return body
    }
    { buf = buf $0 "\n" }
    END {
      L = length(buf); i = 1; depth = 0; awaiting = 0; curkey = ""
      while (i <= L) {
        ch = substr(buf, i, 1)
        if (ch == "\"") {
          s = readstr()
          if (depth == 1) {
            if (awaiting == 0) { curkey = s; awaiting = 1 }
            else { if (curkey == key) { print s; exit } awaiting = 0; curkey = "" }
          }
          continue
        }
        if (ch == "{" || ch == "[") { depth++; i++; continue }
        if (ch == "}" || ch == "]") { if (depth > 0) depth--; i++; continue }
        if (ch == ",") { if (depth == 1) awaiting = 0; i++; continue }
        i++
      }
    }
  ' "$file"
}

# scout_prefill_scan ROOT WORK — fills WORK with the intakePrefill rows.
#
# Writes `prefill` as `<id>\t<runner>\t<title>\t<kind>\t<field>\t<value>\t<source>`
# where an EMPTY value column means the JSON literal null.
scout_prefill_scan() {
  local root="$1" work="$2"
  local id runner title kind field hint value source pm rr
  : > "$work/prefill"

  while IFS="$(printf '\t')" read -r id runner title kind field hint; do
    [ -n "$id" ] || continue
    value=""; source=""
    if [ "$kind" = "scan-derived" ]; then
      case "$id" in
        1)
          value=$(_scout_json_top_string "$root/package.json" name)
          if [ -n "$value" ]; then
            source="package.json name"
          else
            value="${root##*/}"
            source="the project directory's own name — no manifest declared one"
          fi
          ;;
        1_repo_setup)
          # THE URL IS NEVER EMITTED. An https remote can carry a token in its
          # userinfo, and a scan report that helpfully quoted the operator's
          # origin URL would be the §6.2 leak wearing a different hat. The
          # answer the interview needs is whether a remote exists.
          rr=$(awk -F'\t' '$1=="remote_repo_created" { print $2; exit }' "$work/probes" 2>/dev/null)
          if [ "$rr" = "pass" ]; then value="yes"; else value="no"; fi
          source="reality.probes remote_repo_created (the URL itself is deliberately not recorded)"
          ;;
        11_5)
          if [ -s "$work/testcmd" ]; then
            value=$(cut -f1 < "$work/testcmd")
            source=$(cut -f2 < "$work/testcmd")
          else
            value="(none detected)"
            source="Scout found no declared test command and no language convention that applies"
          fi
          ;;
        12)
          pm=$( [ -s "$work/pkgmgr" ] && tr '\n' ' ' < "$work/pkgmgr" | sed -e 's/ *$//' )
          if [ -n "$pm" ]; then
            value="$pm"; source="stack.packageManagers"
          else
            value="(none detected)"; source="no package manager was in evidence"
          fi
          ;;
        13)
          value="(generated from the completed intake)"
          source="run_section_13 writes it from the answers above; it asks no question of its own"
          ;;
      esac
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$id" "$runner" "$title" "$kind" "$field" "$value" "$source" >> "$work/prefill"
  done <<PFIN
$(_scout_prefill_table)
PFIN
  return 0
}

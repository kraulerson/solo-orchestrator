#!/usr/bin/env bash
# scripts/lib/hook-templates.sh
#
# SINGLE SOURCE OF TRUTH for the git-hook bodies init.sh installs and
# scripts/upgrade-project.sh --sync-framework refreshes (BL-099 SLICE-A). Both
# callers source this lib so a hook the operator installed at scaffold time and
# a hook the sync refreshes are generated from identical bytes — no drift.
#
# Contents:
#   • SOIF_PRECOMMIT_OPEN / _CLOSE — markers wrapping the managed region of the
#     fallback pre-commit hook (added by BL-099; shebang stays line 1).
#   • SOIF_TDD_OPEN / _CLOSE — markers wrapping the BL-072 TDD-ordering block in
#     the commit-msg hook (pre-existing markers, hoisted here as constants).
#   • soif_lang_test_pattern <language> — the init.sh language→test-file-pattern
#     table; empty for languages with no distinct test-file convention (rust,
#     unknown). BL-142: this is NOT an install gate — since BL-107-UNIVERSAL-
#     INSTALL, init.sh and the sync install the commit-msg TDD hook for EVERY
#     language; an empty pattern only means the gate classifies test evidence
#     by content/convention (rust's inline #[test] probe, generic conventions
#     for unknown) instead of by filename.
#   • soif_write_precommit_hook <file> — writes the full fallback pre-commit hook
#     (shebang + managed region between markers).
#   • soif_tdd_region_body / soif_emit_tdd_commitmsg_block — the commit-msg
#     TDD-gate managed block (region = markers+body; block = leading blank +
#     region, the exact bytes init.sh appended pre-refactor).
#
# BL-112 (E2E walk findings F8 + F9) — the two load-bearing lines in the EMITTED
# pre-commit hook, both carrying a grep-able marker:
#   • # BL-112-SAST-ERROR   — semgrep needs `--error` or it exits 0 ON FINDINGS,
#     which made the [BLOCKED] arm dead code (an eval(req.query.code) Express RCE
#     was detected, printed, and committed clean). `--severity=ERROR` bounds the
#     gate to high-confidence findings so it stays passable.
#   • # BL-112-STRICT-GATE  — the region's terminal exit is CONDITIONAL, because
#     install-filesystem-gates.sh appends the BL-030 strict-gate block BELOW this
#     region; an unconditional `exit $FAILED` made that block unreachable.
#   • # BL-112-SAST-NOTRUN  — the ONE behaviour for "the scanner did not run",
#     shared by the tool-ABSENT arm and the tool-FAILED (rc>=2) arm: WARN loudly,
#     never block, and never let a not-run scan look like a clean scan. The rc=0
#     arm prints an [OK] receipt for the same reason (a silent pass is
#     indistinguishable from an absent gate — the BL-112 defect class itself).
# NOTE: nothing emitted into the hook may contain the literal marker text of
# either managed block ("SOIF pre-commit fallback" / "SOIF framework gate") —
# installers and tests grep for those strings, and a comment that mentions one is
# indistinguishable from the block itself. Describe them; do not quote them.
# tests/test-bl112-commit-enforcement.sh pins both lines against a REAL scaffold
# and a REAL `git commit`; tests/test-bl099-guard-coverage.sh carries them as
# registry rows.
#
# bash-3.2 safe. Pure emitters — no project-state reads, no network.

# ── Markers ─────────────────────────────────────────────────────────────────
# Pre-commit fallback managed region (BL-099). Kept distinct from CDF's own
# "SOIF framework gate" marker block, which a separate installer manages.
SOIF_PRECOMMIT_OPEN='# >>> SOIF pre-commit fallback'
SOIF_PRECOMMIT_CLOSE='# <<< SOIF pre-commit fallback'
# Commit-msg BL-072 TDD-gate managed block. The "— managed by init.sh" label is
# retained verbatim so a sync-installed block and an init-installed block share
# one marker string (idempotent detection works across both installers).
SOIF_TDD_OPEN='# >>> SOIF BL-072 TDD gate (commit-msg) — managed by init.sh'
SOIF_TDD_CLOSE='# <<< SOIF BL-072 TDD gate'

# ── Language → test-file pattern (init.sh's table) ──────────────────────────
# Echoes the test-file regex for a language, or the empty string for languages
# with no distinct test-file convention (rust uses inline #[cfg(test)]; unknown
# languages have none). BL-142 (stale-doc fix): the hook itself is installed
# for EVERY language by BOTH init.sh and the sync path (BL-107-UNIVERSAL-
# INSTALL — see _bl099_sync_commitmsg_hook, whose own comment is the code-side
# truth); an empty pattern here only switches the gate's test-evidence
# detection from filename convention to content probes.
soif_lang_test_pattern() {
  case "$1" in
    typescript|javascript) printf '%s' "\\.(test|spec)\\.(ts|tsx|js|jsx)$" ;;
    python)                printf '%s' "(test_.*|.*_test)\\.py$" ;;
    rust)                  printf '%s' "" ;;   # Rust tests are inline (#[cfg(test)])
    csharp)                printf '%s' "Tests?\\.cs$" ;;
    kotlin)                printf '%s' "Test\\.kt$" ;;
    java)                  printf '%s' "Test\\.java$" ;;
    go)                    printf '%s' "_test\\.go$" ;;
    dart)                  printf '%s' "_test\\.dart$" ;;
    swift)                 printf '%s' "Tests?\\.swift$" ;;
    *)                     printf '%s' "" ;;
  esac
}

# ── Shared blocked-commit ledger helper (BL-163 / BL-171) ───────────────────
# soif_emit_ledger_helper — emits the best-effort, subshell-confined
# soif_ledger_blocked() helper. ONE SOURCE OF TRUTH: embedded verbatim into BOTH
# the fallback pre-commit hook (BL-163 blocking arms: gitleaks / semgrep / bl125)
# AND the commit-msg hook (BL-171 message-gate refusals: TDD-ordering / Build-
# Loop), so the ~40 helper bytes are never duplicated. The emitted bytes carry
# their own in-hook BEGIN/END marker pair (distinct from each caller's emitter
# fence), so an emitter-level excision of the helper body and an in-hook grep
# never collide. Do NOT quote those marker strings in prose here: the mutation
# suites range-delete them, and a comment that reproduces the literal marker is
# indistinguishable from the marker itself. Quoting: LEDGEREOF is single-quoted so the body is
# emitted literally; generated-project paths (which may contain spaces) are
# expanded only at hook RUN time and always double-quoted.
soif_emit_ledger_helper() {
  cat <<'LEDGEREOF'

# BL-163-BLOCKED-LEDGER-BEGIN
# --- Blocked-commit ledger (BL-163) ---
# BL-163-BLOCKED-LEDGER — Dogfood-4 F-DF4-009: the blocking arms below (gitleaks,
# semgrep, project-tests) set FAILED=1 and the hook exits non-zero BEFORE
# .git/hooks/framework-gate.sh runs, and framework-gate is the ONLY writer of
# terminal_commit_blocked rows — so two real dishonest commit attempts were
# correctly REFUSED yet left NO trace in .claude/bypass-audit.json. This helper
# records the block on the enforcement ledger, naming the arm in details.gate.
# The schema mirrors framework-gate's row (install-filesystem-gates.sh
# record_audit_row): type=terminal_commit_blocked, actor=user_terminal,
# final_outcome=abandoned.
#
# BEST-EFFORT, NEVER A BLAST SHIELD: the append must NEVER weaken the refusal. A
# missing/unreadable append library, an absent jq, or a failed write prints at
# most a one-line [note] and returns 0; the caller's FAILED=1 and the hook's
# terminal exit are untouched. Every call site invokes it as `... || true`, which
# also keeps `set -e` from turning a ledger hiccup into a changed exit path.
soif_ledger_blocked() {
  soif_lg_gate="${1:-unknown}"
  soif_lg_root=$(git rev-parse --show-toplevel 2>/dev/null) || soif_lg_root=""
  if [ -z "$soif_lg_root" ]; then
    echo "[note] BL-163: project root not found — commit still refused, block not logged to the ledger." >&2
    return 0
  fi
  soif_lg_lib="$soif_lg_root/scripts/lib/bypass-audit.sh"
  if [ ! -r "$soif_lg_lib" ]; then
    echo "[note] BL-163: bypass-audit.sh unavailable — commit still refused, block not logged to the ledger." >&2
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "[note] BL-163: jq unavailable — commit still refused, block not logged to the ledger." >&2
    return 0
  fi
  soif_lg_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null) || soif_lg_ts=""
  soif_lg_level=$(jq -r '.enforcement_level // "n/a"' "$soif_lg_root/.claude/manifest.json" 2>/dev/null) || soif_lg_level="n/a"
  [ -n "$soif_lg_level" ] || soif_lg_level="n/a"
  soif_lg_row=$(jq -nc \
    --arg ts "$soif_lg_ts" \
    --arg g "$soif_lg_gate" \
    --arg lvl "$soif_lg_level" \
    '{timestamp:$ts, session_id:null, type:"terminal_commit_blocked", actor:"user_terminal", enforcement_level_at_event:$lvl, details:{gate:$g}, user_response:"n/a", final_outcome:"abandoned"}' 2>/dev/null) || soif_lg_row=""
  if [ -z "$soif_lg_row" ]; then
    echo "[note] BL-163: could not build the ledger row — commit still refused, block not logged to the ledger." >&2
    return 0
  fi
  # Verifier MAJOR (2026-07-23): source + append run in a SUBSHELL. `exit`
  # in a sourced file exits the sourcing shell — a trojan/broken
  # bypass-audit.sh that `exit 0`s would otherwise terminate the whole hook
  # SUCCESSFULLY after "[BLOCKED]" printed, LANDING the refused commit. The
  # subshell confines any exit/parse-error to the append attempt; the
  # refusal and the [note] survive both.
  # shellcheck disable=SC1090
  if ! ( . "$soif_lg_lib" && bypass_audit_append "$soif_lg_root" "$soif_lg_row" ) >/dev/null 2>&1; then
    echo "[note] BL-163: ledger append failed — commit still refused, block not logged to the ledger." >&2
    return 0
  fi
  return 0
}
# BL-163-BLOCKED-LEDGER-END
LEDGEREOF
}

# ── Fallback pre-commit hook ────────────────────────────────────────────────
# soif_precommit_region_body
#   Emits the managed region ONLY: the open marker, the hook body, and the close
#   marker — everything EXCEPT the shebang (which must stay file line 1, outside
#   the region). Used both to write a fresh hook and to refresh the region of an
#   already-marked hook in place. Byte-identical to init.sh's pre-BL-099 hook
#   APART FROM the two marker lines.
soif_precommit_region_body() {
  # Section 1a (open marker, header, set -e, FAILED=0). Open marker is the
  # region's 1st line. Byte-identical to init.sh's pre-BL-099 hook APART FROM
  # the two marker lines and the emitted BL-125 (test-exec) + BL-163 (blocked-
  # ledger) sections inserted between the cats below.
  cat <<'HOOKEOF'
# >>> SOIF pre-commit fallback
# Solo Orchestrator — Fallback Pre-Commit Hook
# Provides baseline enforcement: secret detection + SAST + test co-location check.
# If Development Guardrails for Claude Code is active, its hooks provide deeper coverage.

set -euo pipefail

FAILED=0
HOOKEOF

  # BL-163-LEDGER-EMIT-BEGIN
  # Emitter fence (template-only, NOT emitted): excising this BEGIN..END region
  # drops the blocked-commit ledger helper from the pre-commit hook this lib
  # emits. The helper BYTES live ONCE in soif_emit_ledger_helper (above), shared
  # verbatim with the commit-msg hook (BL-171) — no duplication. The EMITTED bytes
  # carry their own in-hook marker (the BEGIN/END pair, plus a trailing tag on
  # each call site) kept DISTINCT from this fence, so an in-hook grep and an
  # emitter-level excision never collide — the same emitter-fence vs emitted-marker
  # split BL-125 uses for its test-exec arm. (Prose here never reproduces those
  # marker strings literally — the mutation suites range-delete them.)
  soif_emit_ledger_helper
  # BL-163-LEDGER-EMIT-END

  # Section 1b (gitleaks + SAST arms). Continues the managed region.
  cat <<'HOOKEOF'

# --- Secret Detection (gitleaks) ---
if command -v gitleaks &>/dev/null; then
  if ! gitleaks git --staged 2>/dev/null; then
    echo ""
    echo "[BLOCKED] gitleaks detected secrets in staged files."
    echo "  Remove the secrets, use environment variables or a secrets manager,"
    echo "  and rotate any credentials that were exposed."
    FAILED=1
    soif_ledger_blocked gitleaks || true   # BL-163-BLOCKED-LEDGER
  fi
else
  echo "[WARN] gitleaks not found — secret detection skipped."
  echo "  Install: brew install gitleaks (macOS) or https://github.com/gitleaks/gitleaks/releases"
fi


# --- SAST Quick Scan (Semgrep) ---
# BL-112-SAST-NOTRUN — "the scanner did not run" has exactly ONE meaning and ONE
# behaviour here, whatever the cause (tool ABSENT, or tool PRESENT but FAILING):
# WARN LOUDLY, never block. Both arms below call this, and both are pinned by
# tests/test-bl112-commit-enforcement.sh in BOTH directions.
#
# WHY NOT BLOCK ON A TOOL FAILURE (the tempting answer, and the wrong one):
#   • It buys NO security. Anyone who can break the scanner can instead take the
#     strictly easier semgrep-ABSENT path (uninstall it, or shadow it on PATH),
#     which WARNs by documented contract — or simply delete this hook, which is
#     not version-controlled and needs no privileges at all. Blocking one of two
#     equivalent doors, in a room with no walls, is theatre.
#   • It is worse than theatre: it would make BREAKING the scanner strictly more
#     costly than REMOVING it, i.e. it pays people to uninstall the scanner.
#   • And it costs plenty. `p/owasp-top-ten` is a REGISTRY ruleset that semgrep
#     fetches from semgrep.dev with no local-cache fallback, so a developer who
#     is offline / proxied / rate-limited gets rc=2 on EVERY commit. A gate you
#     cannot pass is a gate people --no-verify around — the exact culture BL-112
#     exists to end.
# The attested boundary for "the scanner could not run" is PHASE 3
# (run-phase3-validation.sh + the 3->4 gate), where BL-113 made an un-run scan
# unlaunderable and its skip attested and recorded. This hook is the fast local
# tripwire, not the ledger. What it owes the operator is HONESTY: it must never
# let a not-run scan look like a clean scan.
soif_sast_not_enforced() {
  echo ""
  echo "[WARN] $1"
  echo "  SAST NOT ENFORCED for this commit — the scanner did not run."
  echo "  This is NOT a clean result: nothing was scanned. Phase 3 will require an"
  echo "  attested scan; it cannot be cleared by a scanner that never ran."
}
# BL-182-PARTIAL-COVERAGE — the honest report for a scan that RAN but did not cover
# every staged entry. It is deliberately a SECOND helper rather than a reuse of the
# one above: saying "nothing was scanned" when a subset WAS scanned is its own small
# dishonesty, and this arm's whole job is to describe reality. It carries the SAME
# "SAST NOT ENFORCED" vocabulary, so every operator habit — and every test that greps
# for that string — still sees the loud signal. Like the helper above it WARNs and
# never blocks: an entry we could not read is not evidence of a defect, and blocking
# on unreadable content would pay people to route around the gate (see the rationale
# above). What it must never do is look CLEAN — that is # BL-182-NO-UNEARNED-RECEIPT.
soif_sast_partial_coverage() {
  echo ""
  echo "[WARN] $1"
  echo "  SAST NOT ENFORCED for this commit — the scan did not cover every staged entry."
  echo "  This is NOT a clean result: the entries listed below were never scanned."
  echo "  Phase 3 will require an attested scan; it cannot be cleared by a scan that"
  echo "  skipped part of the commit."
}
# BL-182-NAME-THE-ENTRY — an operator told "coverage was partial" but not WHICH entry
# was missed cannot act on it, and the old whole-commit abort told them nothing at all.
# Every NOTRUN caused by an unreadable staged entry names the entries, one per line.
# bash-3.2 + `set -u` safe: the `${a[@]+"${a[@]}"}` form is required because a bare
# "${a[@]}" on an EMPTY array is an unbound-variable error under `set -u` in bash 3.2.
soif_sast_unread_report() {
  echo "  Staged entries NOT scanned (could not be read from the index):"
  for soif_u in ${soif_idx_unread[@]+"${soif_idx_unread[@]}"}; do
    echo "    - $soif_u"
  done
}
# BL-112-SCAN-COVERAGE — THE RECEIPT IS AN ATTESTATION, SO IT MUST BE EARNED END-TO-END.
# The two guards above cover the entries the materialization loop could not READ. This
# one covers the step AFTER that: semgrep is handed N materialized targets and may
# silently DECLINE some of them. Its documented default `--max-target-bytes` is
# 1,000,000, and an oversize target is dropped with NO error, rc still 0 — so before
# this guard the arm printed `[OK] semgrep: SAST ran on N staged file(s)` counting a
# file semgrep never opened (R-274R-1: 900,037 staged bytes -> REFUSED; the SAME
# content padded to 1,100,032 -> COMMITTED with the [OK] receipt and the innerHTML sink
# in HEAD). That was the FIFTH member of this arm's silent-success class (gitlink,
# `<stage>:` path syntax, PATH_MAX, rename, size) and the FIRST to emit a POSITIVE
# FALSE ATTESTATION rather than merely losing coverage.
#   SO THE FLAG IS NOT THE FIX. `--max-target-bytes=0` retires the size TRIGGER; this
#   guard covers the STEP, by refusing to say [OK] unless semgrep itself reports that it
#   took every target we handed it and parsed every line of what it took.
# WHAT THIS GUARD DOES AND DOES NOT PROVE — STATE IT NARROWLY, IT HAS BEEN OVERSTATED
# ONCE ALREADY, AND THE UNDERSTATEMENT COST A SECOND FALSE ATTESTATION. An earlier
# revision of this comment claimed "per-rule skips, parse-time drops and whatever the next
# semgrep release adds are all covered by construction, with no sixth patch." That was
# FALSE and was caught in review (R-274Rv-1). The two counters it read are both
# TARGET-SELECTION counters — they answer "did semgrep take the file", never "did semgrep
# understand the file" — so a target semgrep accepted and then failed to PARSE satisfied
# every one of them and collected the full [OK] attestation. Measured through the shipped
# emitter on semgrep 1.157.0: an ordinary TypeScript file saved as UTF-16LE (a Windows
# editor default, 142 bytes) carrying `pane.innerHTML = userText` COMMITTED with
# `[OK] semgrep: SAST ran on 1 staged file(s)` while the byte-identical UTF-8 control was
# REFUSED. Adding the parse half did NOT close the class either: review R-274Rv2-1 then
# reproduced a THIRD stage — semgrep takes the file, parses 100% of it, and ABANDONS a
# rule part-way through on its default 5-second per-rule timeout. Both existing halves
# read COMPLETE and the arm certified the commit again. So the class is NOT closed by
# construction, this comment no longer says it is, and the conjunction is now THREE facts
# read out of semgrep's own banner — one per pipeline stage.
# THE NUMBERS, AND WHY THESE AND NOT THE OTHERS. Semgrep's banner carries several counts
# and they measure different stages.
#   • The Scan Status header `Scanning N files with M Code rules:` means "targets that
#     survived semgrep's own target FILTERING". It is fixed by target filtering alone, so
#     it is independent of WHICH rules the live registry happened to resolve — measured
#     2-of-2 for `app.ts + README.md`, 1-of-2 for `app.ts + <oversize>.js`, and 2-of-2 for
#     that same pair once --max-target-bytes=0 is passed. USED — it is the SELECTION half
#     of the invariant (soif_sg_accepted).
#   • `Targets scanned: N` is the plausible-looking alternative and it is REGISTRY-
#     DEPENDENT, which is the reason it is not used. It counts targets whose LANGUAGE
#     matched a rule, so what it reports depends on the resolved ruleset rather than on
#     this commit. With the three --config sets this arm passes it currently agrees with
#     the header on every shape measured (`app.ts + README.md` -> 2, `README.md` alone
#     -> 1, `package.json` alone -> 1) because the resolved set contains `<multilang>`
#     rules that apply to every target regardless of language — semgrep's own table prints
#     `<multilang>  3 rules  2 files`. Drop or change one --config and that stops being
#     true without anything in this arm changing, and the guard would start NOTRUNning
#     ordinary commits — the cry-wolf failure BL-112 exists to end. RULED OUT for being a
#     fact about the registry rather than a fact about this commit.
#     (AN EARLIER REVISION OF THIS BULLET CLAIMED IT READS 1-of-2 FOR `app.ts + README.md`
#     AND 0 FOR `README.md` ALONE. Both were REFUTED by measurement in review, R-274Rv2-5;
#     the argument above is the one the probe actually supports.)
#   • `Parsed lines: ~N%` is `(total_lines - lines_semgrep_core_failed_to_parse) /
#     total_lines`, i.e. the only number in the banner that reports PARSE loss. USED —
#     it is the COMPREHENSION half (soif_sg_parse_full, # BL-186-PARSE-COVERAGE).
#   • `Warning: N timeout error(s) in <target> when running the following rules: [...]`
#     is the only line in the DEFAULT banner that reports a rule which started and did not
#     finish. USED — it is the RULE-EXECUTION third (# BL-187-RULE-COVERAGE). Note the
#     shape difference and do not paper over it: the other two are NUMBERS parsed and
#     compared, this one is a NAMED STRING whose ABSENCE is the good case. That makes it a
#     trigger detector rather than a proof, and the difference is the residue tracked as
#     BL-187.
#   • `Rules run: N` was checked and is NOT a discriminator: the timed-out run reports
#     `Rules run: 29` exactly like a clean one, because a rule that started counts as run.
# WHY `Parsed lines` DOES NOT CRY WOLF, AND WHY ~100.0% IS EXACT RATHER THAN ROUNDED.
# Measured `~100.0%` on 34 ordinary shapes: a.ts+b.ts; ts+md+json+yml; ts+py+go+vue+html;
# all nine at once; a 1.27MB source file; a minified bundle; CRLF; a UTF-8 BOM; emoji; an
# empty file; a 2000-line source; a large package-lock.json; and one well-formed file per
# language across ts/tsx/js/py/go/java/cs/php/rs/kt/swift/rb/Dockerfile/tf/sh/sql/yml/
# css/md. Zero false alarms. And the value cannot round UP into a false pass: semgrep's
# pretty_print_percentage CLAMPS anything above 99.9 to `99.9` unless numerator ==
# denominator exactly, so `~100.0%` means literally zero lines lost, not "about all of
# them". It is unlike `Targets scanned` in precisely the way that matters here.
# FAIL CLOSED, ALWAYS — AND THE THIRD FACT IS THE ONE EXCEPTION, SAID OUT LOUD. If either
# NUMERIC line is missing, duplicated or unparseable — an older or newer semgrep, a future
# output redesign — the corresponding variable stays EMPTY and the arm takes the loud
# NOTRUN path. It must never fall through to [OK]: a parser that cannot read the receipt's
# evidence and prints the receipt anyway IS the silent-success class, wearing the coat of
# the code that was supposed to end it. The cost of that choice is real and is accepted
# deliberately, and it is TWO anchored banner lines rather than one: on a host where either
# never appears, EVERY commit reports NOT ENFORCED. That is loud, honest and non-blocking
# (this arm never blocks on a can't-scan), and it is strictly better than a receipt nobody
# can trust. The two lines are highly correlated failures — both come from semgrep's
# text-output module — so the second anchor adds little independent cliff risk, but it does
# add some, and the remaining anchor-fragility is tracked rather than waved away (BL-186).
#   THE TIMEOUT CHECK CANNOT HAVE THAT SHAPE AND THIS COMMENT WILL NOT PRETEND IT DOES.
#   Its good case is the line's ABSENCE, so "absent => fail closed" would NOTRUN every
#   commit ever made. It is therefore a POSITIVE DETECTOR for a spelling semgrep emits
#   today, verified on 1.157.0, and a future release that renames the warning re-opens
#   exactly the hole R-274Rv2-1 found — silently. That is a real asymmetry between the
#   three facts, it is not fixable from the default banner (semgrep exposes per-rule
#   timing only under --time/--json, which this arm does not use), and it is filed as
#   BL-187 rather than described as closed. Anchor on the atom `timeout error(s)` and
#   NOT on the whole sentence: semgrep WRAPS that warning across two lines at ~120
#   columns even when stderr is a file, so matching the full "…when running the following
#   rules:" phrase would fail on the wrap.
# THE RESIDUE, NAMED (BL-186) — AND THE EXACT LIMIT OF WHAT THIS GUARD SEES. `Parsed
# lines` is driven by `ignore_log.core_failure_lines_by_file`, so it moves if and only if
# semgrep-core REPORTS a parse failure. That is a narrower thing than "semgrep understood
# the file", and the gap is the residue. Measured on 1.157.0, same 68-byte innerHTML sink
# in each, invoked exactly as this arm invokes it:
#   • UTF-16LE with a BOM -> ~50.0%, UTF-16BE with a BOM -> ~0.0%. CAUGHT, and DETERMINISTIC
#     (5/5 identical runs). This is the shape a Windows editor writes and it is the trigger
#     that was reproduced against the previous revision (R-274Rv-1).
#   • A 40KB random binary blob staged as `vendor.js` -> CAUGHT ONLY SOMETIMES: 4 of 10
#     runs read ~95.3-99.4% and forfeited the receipt, 6 of 10 read ~100.0% and did not.
#     Whether semgrep-core happens to log a failure depends on the bytes. Do NOT describe
#     this trigger as closed; it is reduced.
#   • An unparseable source file: sometimes ~0.0% (caught), sometimes ~100.0% — semgrep's
#     parsers are error-recovering, and a recovered parse reports no loss.
#   • UTF-16LE or UTF-16BE with NO BOM, and a file with embedded NUL bytes: NEVER caught.
#     All report `Targets scanned: 1` AND `Parsed lines: ~100.0%` AND zero findings.
#   • A PER-RULE TIMEOUT ON A DENSE >1MB SOURCE FILE: it was never caught by these two and
#     that is the row this paragraph was missing (R-274Rv2-1). It is not an exotic
#     encoding — it is a file `tsc` compiles happily. Measured through the shipped emitter
#     on 1.157.0, sink on line 2 of an otherwise ordinary generated-looking .ts, padding
#     that is CODE rather than comments: 196,561 and 600,561 bytes -> REFUSED [BLOCKED];
#     1,216,567 bytes -> COMMITTED with the full `[OK]` receipt and the sink in HEAD,
#     DETERMINISTICALLY (5/5). semgrep printed `Scanning 1 file`, `Targets scanned: 1`,
#     `Parsed lines: ~100.0%`, `✅ Scan completed successfully.` and rc=0 — every fact both
#     halves check read COMPLETE — plus one line neither of them read: `Warning: 1 timeout
#     error(s) in …heavy.ts when running the following rules:
#     [javascript.browser.security.insecure-document-method…]`. NOW CAUGHT, by
#     # BL-187-RULE-COVERAGE, which is why this row reads differently from the ones above.
#     THE PADDING SHAPE IS THE WHOLE POINT: the same sink under >1MB of COMMENT padding
#     (1,253,093 bytes) is BLOCKED, because comments are cheap to match. A fixture that
#     pads with comments is the one large-file shape that structurally cannot provoke this,
#     which is exactly how the first revision of this guard shipped believing it was safe.
# So: this guard closes the deterministic BOM'd-UTF-16 trigger and the per-rule-timeout
# trigger, reduces the binary-blob one, and does not touch the rest. It is a fourth and a
# fifth precondition, not a closure. The remainder is BL-186 (encoding) and BL-187 (rule
# execution), and the phrase "covered by construction" does not belong anywhere near this
# arm — it is what the previous revision claimed and it was false.
#
# THREE WARN HELPERS NOW, NOT ONE, AND THE SPLIT IS DELIBERATE — same reasoning
# soif_sast_partial_coverage records for ITS split from soif_sast_not_enforced. Saying
# "nothing was scanned" when a subset WAS scanned is a small dishonesty; so is saying
# "these entries were never scanned" when what we actually know is "one of these was".
# All three carry the SAME "SAST NOT ENFORCED" vocabulary, so every operator habit and
# every test that greps for that string still sees the loud signal, and all three WARN
# without blocking — a target the scanner declined is not evidence of a defect, and
# blocking on it would pay people to route around the gate (rationale above). The two
# lines that differ are parameters here rather than a fourth copy of the helper.
soif_sast_coverage_warn() {
  echo ""
  echo "[WARN] $1"
  echo "  SAST NOT ENFORCED for this commit — $2"
  echo "  Phase 3 will require an attested scan; it cannot be cleared by a scan whose"
  echo "  coverage of the staged commit is unproven."
}
soif_sast_scan_coverage_report() {
  if [ -n "${soif_sg_accepted:-}" ]; then
    echo "  Coverage: semgrep accepted $soif_sg_accepted of the ${#soif_idx_files[@]} staged file(s) handed to it."
  else
    echo "  Coverage: UNVERIFIED — semgrep's scan-status line was absent or unreadable"
    echo "  (${#soif_idx_files[@]} staged file(s) were handed to it; how many it opened is unknown)."
  fi
  # # BL-186-PARSE-COVERAGE — the SECOND fact, and it is a different fact. "Accepted" is
  # about target selection; this is about whether the bytes inside those targets were
  # ever turned into something a rule could match. Both are printed on every forfeited
  # receipt, always, even when only one of them is the reason: an operator told "coverage
  # was partial" who then fixes the wrong half re-commits straight back into the other.
  if [ -n "${soif_sg_parsed:-}" ]; then
    echo "  Parse coverage: semgrep reports it parsed ${soif_sg_parsed}% of the lines in those file(s)."
  else
    echo "  Parse coverage: UNVERIFIED — semgrep's parse-coverage line was absent or"
    echo "  unreadable, so how much of the staged content it understood is unknown."
  fi
  # # BL-187-RULE-COVERAGE — the THIRD fact, and again a different one. Selection is which
  # targets semgrep took; parse is whether their bytes became something a rule could match;
  # this is whether the rules then FINISHED running against them. Printed on every
  # forfeited receipt for the same reason the other two are: an operator who fixes the
  # encoding and re-commits into an abandoned rule has been sent to the wrong half twice.
  #   AND IT IS THE ONE GAP THIS ARM CAN ATTRIBUTE PER FILE. Semgrep's default output does
  #   not say which target it DECLINED (hence the "all of them are listed" hedge below),
  #   but the timeout warning names the target AND the exact rule ids. Surfacing it is
  #   strictly the # BL-182-NAME-THE-ENTRY contract being honoured where it can be.
  if [ "${soif_sg_timeouts:-0}" -gt 0 ]; then
    echo "  Rule coverage: semgrep reported ${soif_sg_timeouts} rule-timeout warning(s). At least one"
    echo "  rule was ABANDONED part-way through a target, so that rule never matched it."
    # The warning WRAPS across two lines at ~120 columns even when stderr is a file, so an
    # anchor-line-only excerpt would cut the rule ids off. Print from the anchor to the
    # first blank line (semgrep's own block separator), capped at 10 lines total across all
    # warnings so a many-target commit cannot dump the banner into the transcript. The
    # temp-tree prefix is mapped off with the same sed the findings use — an operator shown
    # a /var/folders/… path they cannot resolve has been told nothing.
    awk '/timeout error\(s\)/{soif_t=1} soif_t{ if ($0 ~ /^[[:space:]]*$/) { soif_t=0; next } print; soif_m=soif_m+1; if (soif_m>=10) exit }' "$soif_sg_err" 2>/dev/null \
      | sed "s#${soif_idx_tree}/[0-9][0-9]*/##g" | sed 's/^/    /'
  else
    echo "  Rule coverage: semgrep reported no rule-timeout warnings."
  fi
  # NAMED, not counted — the # BL-182-NAME-THE-ENTRY contract. Semgrep's DEFAULT output
  # does not say WHICH target it declined (only --verbose does, and turning that on for
  # every commit would bury the operator in per-rule noise on the one path where stderr
  # is surfaced verbatim). So this names the exact set that was handed over and says
  # plainly that attribution stops there, rather than implying a precision it does not
  # have. Semgrep's own skip summary follows and usually identifies the entry outright
  # ("Files larger than 1.0 MB: 1" against a listed set of three is not a puzzle).
  echo "  Staged entries handed to the scanner (semgrep's default output does not"
  echo "  attribute coverage per file, so all of them are listed):"
  for soif_c in ${soif_idx_rel[@]+"${soif_idx_rel[@]}"}; do
    echo "    - $soif_c"
  done
  echo "  Re-run semgrep with --verbose on these paths to see exactly what it skipped."
  # Bounded excerpt of semgrep's own Scan Summary skip section, which usually identifies
  # the entry outright ("Files larger than 1.0 MB: 1" against a listed set of three is
  # not a puzzle). TWO independent stop conditions on purpose: the section's bullet lines
  # are all INDENTED, so the first unindented line ends it, and an 8-line cap catches the
  # case where a future semgrep stops indenting. An unbounded range would dump the whole
  # banner — the version-check notice included — into the operator's commit transcript.
  awk '/Scan skipped/{soif_f=1} soif_f{ if ($0 !~ /^[ \t]/) exit; print; soif_n=soif_n+1; if (soif_n>=8) exit }' "$soif_sg_err" 2>/dev/null | sed 's/^/    /'
}

if command -v semgrep &>/dev/null; then
  # Scan only staged files for fast pre-commit feedback.
  #
  # NUL-delimited read into an array rather than `| xargs -0 semgrep …`: xargs
  # COLLAPSES the utility's exit code (BSD xargs -> 1, GNU xargs -> 123 for ANY
  # non-zero), which makes semgrep's "blocking findings" code (1) indistinguish-
  # able from a semgrep TOOL failure (>=2: bad config, registry unreachable,
  # parse error). The two must be told apart — one blocks, the other warns.
  # BL-179-STAGED-FILTER — the filter is ACMRT, and the inclusion of R and T AND the
  # exclusion of D are each load-bearing. They are not the same decision as the BL-125
  # test arm's ACMDR (~120 lines below) and must not be copied from it.
  #   THE TEST THIS FILTER MUST PASS: does the status letter denote a staged entry that
  #   HAS SCANNABLE CONTENT OF ITS OWN? A,C,M,R,T all do; D does not. Anything else and
  #   the receipt below stops meaning what it says.
  #   R (RENAME) MUST BE INCLUDED. `diff.renames` defaults to TRUE, so a commit that
  #   renames a file AND edits it in the same breath is reported as ONE status-R entry
  #   — which the old ACM filter EXCLUDED. soif_staged came back EMPTY, and since the
  #   arm below was a `-gt 0` test with NO `else`, the scanner produced NO OUTPUT AT
  #   ALL: no [OK], no [BLOCKED], and not even the loud NOTRUN every other can't-scan
  #   path routes to. A routine rename-and-edit refactor walked an innerHTML sink past
  #   the gate in total silence (BL-179, reproduced through the real emitter, the real
  #   .git/hooks/pre-commit and a real `git commit`). For an R entry `--name-only -z`
  #   emits the DESTINATION path, and `:0:<dest>` resolves to its staged blob, so the
  #   materialization loop below needs no change at all.
  #   T (TYPE CHANGE) MUST BE INCLUDED, and this one is the quieter hole because it does
  #   NOT route to the empty-staged report. Replacing a symlink with a regular file is
  #   ordinary repo hygiene; git calls it T, the old ACMR filter dropped it, and a CLEAN
  #   SIBLING in the same commit kept soif_staged non-empty — so the arm sailed past the
  #   # BL-179-EMPTY-STAGED else and printed `[OK] … ran on N staged file(s)` with N
  #   counting only the sibling while the dropped entry carried an innerHTML sink
  #   (R-WPC-1, reproduced through the real emitter and a real `git commit`: verdict
  #   COMMITTED, sink present in the committed tree). A truncated TARGET SET produces
  #   exactly the unearned receipt # BL-182-NO-UNEARNED-RECEIPT guards against, but the
  #   loop never sees the entry, so that guard cannot fire — only the filter can.
  #   T IS SAFE WHERE D IS NOT, and the difference is the whole reason both letters are
  #   spelled out here. Verified on git 2.50.1: `git cat-file -t ":0:<path>"` returns
  #   `blob` for a T entry in BOTH directions — symlink->file (index mode 100644) and
  #   file->symlink (index mode 120000) — and for gitlink->file. T therefore never
  #   manufactures a phantom unreadable entry. (A ->gitlink T would present index mode
  #   160000 and be absorbed by # BL-132-GITLINK-SKIP, which is already correct. A bare
  #   permission flip is reported M, not T, and was always covered.)
  #   D (DELETION) MUST STAY EXCLUDED. The BL-125 arm includes D because it must RUN
  #   THE TESTS when a sanitizer is deleted; THIS arm must SCAN CONTENT, and a deleted
  #   path has no staged content to scan. Including it hands the loop an index entry
  #   whose `git cat-file -t ":0:<path>"` fails (verified: exit 128) — manufacturing a
  #   phantom unreadable entry, i.e. a fresh instance of the very class BL-182 retires
  #   below. Pinned in all three directions by the ACMRT->ACMT, ACMRT->ACMR and
  #   ACMRT->ACMDRT mutation cases in tests/test-bl132-sast-index-scan.sh.
  soif_staged=()
  while IFS= read -r -d '' soif_f; do
    soif_staged+=("$soif_f")
  done < <(git diff --cached --name-only --diff-filter=ACMRT -z)

  if [ "${#soif_staged[@]}" -gt 0 ]; then
    # semgrep splits its output cleanly: FINDINGS go to stdout, the scan banner
    # AND its fatal errors go to stderr. We capture BOTH to temp files: stderr so a
    # tool failure's diagnostic survives (the only place it appears), and — new for
    # BL-132 — stdout so finding paths can be rewritten from the temp index tree
    # back to real repo-relative paths before they are shown.
    soif_sg_err="$(mktemp)"
    soif_sg_out="$(mktemp)"
    # BL-132-INDEX-SCAN — scan the STAGED CONTENT, not the worktree bytes. The old
    # arm handed semgrep the staged PATHNAMES, so semgrep read whatever was on disk:
    # `git add app.ts` (vuln), overwrite app.ts clean, and the COMMITTED bytes were
    # never scanned — the flaw shipped with an [OK] receipt (BL-132 repro; `git add
    # -p` / stage-then-edit share the hole). Materialize each staged blob into a
    # throwaway tree that mirrors the repo layout (same relative path + extension so
    # semgrep still picks the language, under a per-entry subdir — see the
    # BL-178-PER-INDEX-DIR note in the loop), then hand semgrep the EXPLICIT
    # materialized FILE targets (collected in soif_idx_files), never the tree dir.
    #   WHY EXPLICIT FILES, NOT THE DIRECTORY (verifier F1): pointing semgrep at a
    #   directory re-engages its built-in default .semgrepignore — staged sinks under
    #   tests/ test/ build/ dist/ vendor/ node_modules/ and *.min.js are then SILENTLY
    #   skipped and the commit lands with a false [OK] receipt. `--no-git-ignore` does
    #   NOT disable those built-in defaults. Explicit file targets bypass ignore
    #   filtering by semgrep's own documented semantics and restore the pre-BL-132
    #   contract by construction.
    #   THE RECEIPT COUNTS TARGETS, NOT STAGED ENTRIES. Since # BL-132-GITLINK-SKIP
    #   the two can legitimately differ (a staged submodule gitlink has no bytes to
    #   scan), so the "[OK] … ran on N staged file(s)" line reports
    #   ${#soif_idx_files[@]} — what was ACTUALLY targeted — and zero targets routes
    #   to NOTRUN (# BL-132-EMPTY-TARGETS) rather than claiming a scan.
    # bash-3.2 and NUL-safe: soif_staged was read -z above; each path is round-tripped
    # through `git cat-file blob :0:<path>` — the STAGE-EXPLICIT form, see
    # # BL-132-STAGE0-REF in the loop; a bare `:<path>` is NOT safe for arbitrary
    # staged names. A pathname git cannot express (a NUL byte) cannot be staged, so it
    # cannot reach here.
    # BL-182-PER-ENTRY-SKIP — THE ALL-OR-NOTHING `break` IS RETIRED. Every failure
    # point in this loop used to do `soif_idx_ok=0; break`, which DISCARDED every
    # sibling already materialized and routed the WHOLE commit to NOTRUN — so a sink
    # staged in a readable sibling LANDED. That is strictly worse than scanning
    # nothing, and the mechanism produced THREE separate defects in this one loop: a
    # submodule gitlink (R-270-1), a repo-root path matching git's `:<stage>:<path>`
    # syntax (R-270-1B), and a repo-relative path too long to express under the
    # `mktemp -d` root (BL-182). Patching a fourth trigger was the wrong move; the
    # CLASS is retired instead. Each unreadable entry is recorded in soif_idx_unread
    # and the loop CONTINUES, so coverage degrades entry-by-entry instead of
    # collapsing. The honesty half is non-negotiable and lives after the loop:
    #   • any finding in what DID materialize still BLOCKS (# BL-182-PARTIAL-STILL-BLOCKS)
    #   • a CLEAN scan over a PARTIAL set is NOT a clean scan and never earns the [OK]
    #     receipt (# BL-182-NO-UNEARNED-RECEIPT)
    #   • every NOTRUN caused by an unreadable entry NAMES it (# BL-182-NAME-THE-ENTRY)
    # "Scan the readable subset" without those three is just the silent-success class
    # wearing a smaller coat.
    soif_idx_tree="$(mktemp -d)"
    soif_idx_files=()
    # soif_idx_rel is soif_idx_files' REPO-RELATIVE twin, appended at the same and only
    # site, so index i of one is index i of the other. It exists so
    # # BL-112-SCAN-COVERAGE can NAME the entries handed to semgrep in the operator's
    # own path vocabulary; the temp-tree paths in soif_idx_files are meaningless to them
    # (that is the whole reason findings get the # BL-178-PER-INDEX-DIR prefix stripped).
    soif_idx_rel=()
    soif_idx_unread=()
    soif_idx_n=0
    for soif_p in "${soif_staged[@]}"; do
      # BL-178-PER-INDEX-DIR — one subdir PER STAGED ENTRY ($tree/<n>/<relpath>),
      # never one flat tree. On a case-INSENSITIVE filesystem (macOS APFS, Windows
      # NTFS) two staged paths differing only in case — App.ts (the vuln) and
      # app.ts (clean) — resolve to the SAME on-disk dest in a flat tree, so the
      # second write CLOBBERS the first: the vuln blob is LOST and the commit lands
      # with a false [OK] receipt (BL-178, reproduced). The F2 size check below
      # cannot see it — each write is internally consistent; it is the EARLIER blob
      # that was destroyed. Per-entry subdirs make the collision unrepresentable.
      # <n> is the STAGED POSITION, and the path-mapping sed below strips the whole
      # "$soif_idx_tree/<n>/" prefix back off finding paths so the operator is shown
      # the REAL repo-relative path — never a temp path, never a bare index number.
      soif_idx_n=$((soif_idx_n + 1))
      # BL-132-GITLINK-SKIP — a staged SUBMODULE GITLINK is index mode 160000, NOT a
      # blob: `git cat-file blob :0:sub` exits 128. Aborting the loop on it (the first
      # cut's bare `break`) DISCARDED every already-materialized target and routed
      # the WHOLE commit to NOTRUN — so a vulnerability staged in a sibling file
      # LANDED, and the trigger is routine (`git submodule add` or a pointer bump in
      # the same commit as application code). A gitlink has no bytes to scan, so
      # SKIP it and keep scanning its siblings.
      #   THIS IS NOT A BLANKET "unreadable => skip". The skip is gated on the index
      #   MODE being 160000, read back with a `:(literal)` pathspec so a path
      #   containing glob metacharacters or spaces cannot mis-resolve. Anything that
      #   is neither a blob nor a gitlink is content we OWE the operator a scan of,
      #   and still routes to the loud NOTRUN below. Verified: pruning a real blob's
      #   object makes `cat-file -t` fail while ls-files still reports mode 100644.
      #   THE TWO OUTCOMES ARE NO LONGER THE SAME SHAPE (# BL-182-PER-ENTRY-SKIP): a
      #   gitlink `continue`s with NO trace, because it is not content and its absence
      #   from the scan costs the operator nothing; an unreadable entry `continue`s
      #   INTO soif_idx_unread, which forfeits the [OK] receipt for the whole commit
      #   and is reported by name. Keep that distinction — collapsing them would let a
      #   real unscanned blob buy a clean-looking commit.
      #   CAUTION, and the reason # BL-132-STAGE0-REF below exists: a failing
      #   `cat-file -t` does NOT imply a missing/corrupt object. An earlier revision
      #   of this comment enumerated it as the only other cause; R-270-1B REFUTED
      #   that — it also fails for a perfectly HEALTHY blob when the reference itself
      #   is mis-parsed. Widen this skip only against a re-derived enumeration.
      # BL-132-STAGE0-REF — address the index at an EXPLICIT stage, `:0:<path>`, never
      # a bare `:<path>`. Git reads `:<0-3>:<path>` as a MERGE-STAGE reference, so for
      # a staged file whose REPO-ROOT name begins with `0:`..`3:` (e.g. `2:evil.js`)
      # the bare form parses as "stage 2 of evil.js" and FAILS on a fully readable
      # blob. That is no gitlink, so the skip above does not fire: the entry fell
      # through to the loop's then-existing `soif_idx_ok=0; break` (since retired by
      # # BL-182-PER-ENTRY-SKIP), discarding every sibling target and NOTRUNning the
      # WHOLE commit while a vulnerable sibling LANDED — a security-lane
      # regression versus main, the same "one bad entry blinds the commit" shape as the
      # gitlink bug (R-270-1B, reproduced A/B through the real emitter). THE STAGE-0
      # PREFIX IS STILL LOAD-BEARING after that retirement: without it such an entry
      # becomes an UNREADABLE entry, which forfeits the commit's [OK] receipt and
      # NOTRUNs on content that was perfectly readable all along. Boundaries,
      # verified on git 2.50.1: `0:`/`1:`/`2:`/`3:` at repo ROOT fail bare, while
      # `4:x.js` (only 0-3 are stage digits), `2evil.js` (the colon is required) and
      # `sub/2:x.js` (root only) all resolve bare. `:0:` resolves ordinary paths
      # identically, so it is a strict improvement — and ALL THREE cat-file sites in
      # this loop must carry it; a bare one anywhere reopens the hole. The `:(literal)`
      # probe above is a PATHSPEC, not a revision, and was verified immune to this
      # (a `2:x.js`-shaped path resolves correctly) — it is deliberately left as-is.
      soif_idx_type=$(git cat-file -t ":0:$soif_p" 2>/dev/null) || soif_idx_type=""
      if [ "$soif_idx_type" != "blob" ]; then
        if git ls-files -s -- ":(literal)$soif_p" 2>/dev/null | grep -q '^160000 '; then
          continue
        fi
        soif_idx_unread+=("$soif_p"); continue
      fi
      soif_idx_dest="$soif_idx_tree/$soif_idx_n/$soif_p"
      # The `2>/dev/null` used to sit on `mkdir -p` while the `$(dirname …)` command
      # substitution ran FIRST with UNREDIRECTED stderr — so a `dirname: …: File name
      # too long` leaked raw into the operator's commit transcript (BL-182, observed).
      # dirname carries its own redirect now, and an empty result is treated as a
      # failure rather than being passed to `mkdir -p ""`.
      soif_idx_ddir=$(dirname "$soif_idx_dest" 2>/dev/null) || soif_idx_ddir=""
      if [ -z "$soif_idx_ddir" ] || ! mkdir -p "$soif_idx_ddir" 2>/dev/null; then
        soif_idx_unread+=("$soif_p"); continue
      fi
      # BRACE-GROUPED REDIRECT, deliberately: bash applies redirections LEFT TO RIGHT,
      # so `cmd > "$dest" 2>/dev/null` reports a failure to OPEN $dest before the
      # `2>/dev/null` is in force — a >255-byte name component then prints a raw
      # "File name too long" to the operator's terminal. Redirecting the GROUP puts
      # /dev/null in place first, so the open failure is swallowed and handled here.
      { git cat-file blob ":0:$soif_p" > "$soif_idx_dest"; } 2>/dev/null || { soif_idx_unread+=("$soif_p"); continue; }
      # F2 — positive content check: the materialized dest MUST match the staged
      # blob's byte size, so a git read that returns 0 while writing nothing or a
      # short/partial file cannot slip a non-empty staged blob past the scan as an
      # empty file. A mismatch routes to the loud NOTRUN below, never a silent pass.
      soif_idx_want=$(git cat-file -s ":0:$soif_p" 2>/dev/null) || soif_idx_want=""
      soif_idx_got=$(wc -c < "$soif_idx_dest" 2>/dev/null | tr -d '[:space:]') || soif_idx_got=""
      if [ -z "$soif_idx_want" ] || [ "$soif_idx_got" != "$soif_idx_want" ]; then soif_idx_unread+=("$soif_p"); continue; fi
      soif_idx_files+=("$soif_idx_dest")
      soif_idx_rel+=("$soif_p")
    done
    if [ "${#soif_idx_files[@]}" -eq 0 ]; then
      if [ "${#soif_idx_unread[@]}" -gt 0 ]; then
        # Nothing at all could be snapshotted — honest NOTRUN (# BL-112-SAST-NOTRUN):
        # never a silent pass, and never a false block on content we could not read.
        # The message text is unchanged from the pre-BL-182 whole-commit abort so
        # operator docs and existing pins still match; what is NEW is that it now
        # NAMES the entries (# BL-182-NAME-THE-ENTRY) instead of leaving the operator
        # to guess which of their staged files went unscanned.
        soif_sast_not_enforced "could not materialize staged content for scanning — SAST skipped."
        soif_sast_unread_report
      else
        # BL-132-EMPTY-TARGETS — nothing scannable was materialized (e.g. a submodule
        # POINTER-BUMP commit stages only a gitlink). The scan did not happen, so the
        # [OK] receipt below would be a lie: route to the same honest NOTRUN. This is
        # the receipt-honesty half of BL-132-GITLINK-SKIP — skipping a gitlink must
        # never buy a clean-looking commit. Reached only when NOTHING was unreadable,
        # so it can still speak plainly about non-blob entries.
        soif_sast_not_enforced "no scannable staged content (all staged entries are non-blob, e.g. submodule gitlinks) — SAST skipped."
      fi
    else
      set +e
      # BL-112-SAST-ERROR — `--error` is LOAD-BEARING. Semgrep exits 0 even when it
      # finds (and prints!) issues unless --error is passed, so without it the
      # [BLOCKED] arm below is UNREACHABLE and an `eval(req.query.code)` Express RCE
      # is detected, printed, and committed clean (E2E walk finding F9).
      # `--severity=ERROR` bounds the gate to semgrep's high-confidence rules: the
      # gate must block real issues without becoming so noisy that operators route
      # around it. WARNING/INFO findings still surface in the Phase-3 scanners + CI.
      # BL-118-DOMXSS-CONFIG — p/owasp-top-ten contains NO browser DOM-sink rules:
      # a stored DOM XSS (`pane.innerHTML = userText`) scanned CLEAN, printed the
      # [OK] receipt, and shipped to main (Dogfood-2 finding F-DF2-007). The browser
      # ruleset is severity=ERROR in the registry, so it survives the
      # --severity=ERROR bound and flags innerHTML/outerHTML/document.write sinks.
      # BL-131-DOM-SINKS — the project-owned DOM-sink ruleset (under .semgrep/,
      # shipped by init.sh) covers the sinks NO registry rule catches:
      # insertAdjacentHTML, jQuery .html(), and innerHTML/document.write inside
      # .vue/.html (which the registry's js/ts rules cannot reach). Referenced by the
      # repo-relative path (git runs hooks at the work-tree root); passed
      # UNCONDITIONALLY so a missing/deleted file makes semgrep exit >=2 and the
      # NOTRUN arm fires LOUDLY — coverage can never silently vanish. Each --config
      # rides its OWN continuation line so a mutation test can strip exactly one;
      # removing either DOM line re-blinds the gate.
      # BL-112-MAX-TARGET-BYTES — 0 DISABLES semgrep's size filter, whose documented
      # default is 1,000,000 bytes. Without this, a staged blob one byte over that is
      # dropped SILENTLY, rc stays 0, and the [OK] receipt below counts a file semgrep
      # never opened (R-274R-1). A >1MB staged source file is unusual but entirely
      # legal — a generated bundle, a vendored lib, a fixture corpus — and "large" is
      # not "safe": the sink sat on line 2. This rides its OWN continuation line, like
      # each --config above, so a mutation test can strip exactly one thing.
      #   THE FLAG IS ONLY HALF THE FIX. It retires this TRIGGER; # BL-112-SCAN-COVERAGE
      #   below retires the CLASS, and the two are proved independently — with the flag
      #   stripped, the coverage guard must still refuse the receipt.
      #   THE LATENCY TRADE IS DELIBERATE, AND THE RATIONALE PREVIOUSLY RECORDED HERE WAS
      #   MEASURABLY WRONG IN BOTH DIRECTIONS (R-274Rv2-2). It said (a) "if semgrep cannot
      #   cope it exits >=2 and the arm WARNs loudly" and (b) "keep the cap and let the
      #   coverage guard turn every oversize entry into a NOTRUN is worse — all of the cost
      #   and none of the coverage." Measured on 1.157.0, both fail for the case this
      #   comment's own examples name (a generated bundle, a vendored lib):
      #     (a) semgrep does NOT exit >=2. On a dense 1,216,567-byte .ts it exits 0 and
      #         prints `✅ Scan completed successfully.` while a rule quietly times out.
      #     (b) With the cap left at its 1,000,000 default the SELECTION guard SEES the
      #         shortfall (`accepted 0 of 1`) and forfeits the receipt. With the cap
      #         disabled semgrep accepts the file, abandons the rule on its per-rule
      #         timeout, reports full selection AND full parse coverage, and — before
      #         # BL-187-RULE-COVERAGE existed — the arm CERTIFIED the commit. The flag
      #         converted a guard-VISIBLE shortfall into a guard-INVISIBLE one.
      #   THE FLAG IS STILL RIGHT, for the reason the old text got right by accident: for
      #   LOW-COMPLEXITY oversize blobs it buys real coverage (verified: the >1MB
      #   comment-padded fixture is REFUSED with the flag and merely NOTRUN without it).
      #   What made it safe is not the flag, it is # BL-187-RULE-COVERAGE landing beside
      #   it. Do not restate (a) or (b); they are refuted, and they are recorded here so
      #   the next reader does not re-derive them.
      #   THE PER-RULE TIMEOUT IS LEFT AT ITS 5s DEFAULT, DELIBERATELY AND AS A DEFERRAL.
      #   `--timeout=0` removes the limit and DOES catch the dense fixture ([BLOCKED],
      #   ~11s wall on this host) — but "no limit" in a pre-commit hook means a rule with
      #   catastrophic backtracking hangs the operator's terminal with no message, which is
      #   worse than a forfeited receipt on every axis this arm cares about: not loud, not
      #   honest, and indistinguishable from a crash. Picking a finite larger value is a
      #   latency-budget POLICY call, not an implementation detail. Filed as BL-187.
      semgrep scan --config=p/owasp-top-ten \
        --config=r/javascript.browser.security.insecure-document-method \
        --config=.semgrep/soif-dom-sinks.yml \
        --max-target-bytes=0 \
        --no-git-ignore \
        --severity=ERROR --error ${soif_idx_files[@]+"${soif_idx_files[@]}"} >"$soif_sg_out" 2>"$soif_sg_err"
      soif_sg_rc=$?
      set -e
      # BL-112-SCAN-COVERAGE (parse) — read back how many targets semgrep says it
      # accepted. Rationale, the choice of counter, and the fail-closed contract are on
      # soif_sast_scan_coverage_report above; this is only the parse, and it is written
      # so that EVERY failure mode lands on the empty string:
      #   • require the Scan Status header to appear EXACTLY ONCE (0 or 2+ => unparseable,
      #     which also makes a future multi-product banner fail closed instead of guessing);
      #   • sanitize the captured value through the same case-glob the rest of this hook
      #     uses for numbers, so a non-numeric capture cannot reach an arithmetic test and
      #     flip the gate the way a multi-line CURRENT_PHASE once did;
      #   • guard every command with `|| …=""` so `set -e` cannot abort the hook here.
      # Header shape on semgrep 1.157.0: two leading spaces, "Scanning <N> file[s] with
      # <M> Code rule[s]:" and no ANSI escapes when stderr is a file (which it always is
      # here). BOTH NUMBERS SINGULARIZE and both spellings are matched — the file count at
      # N=1 ("Scanning 1 file"), and the RULE count at M=1 ("with 1 Code rule:"), which was
      # verified by running semgrep against a single-rule --config and reading back
      # `Scanning 1 file with 1 Code rule:` (R-274Rv2-8). The rule plural was hard-required
      # here until that measurement, which made a one-rule resolved set a PERMANENT NOTRUN
      # cliff: soif_sg_accepted would stay empty on every commit, forever, in every
      # generated project. Widening to accept a spelling semgrep really emits only ever
      # admits a real header; an unrecognised one still leaves the variable empty.
      soif_sg_hdr_n=$(grep -cE '^[[:space:]]*Scanning [0-9][0-9]* files? with [0-9][0-9]* Code rules?:[[:space:]]*$' "$soif_sg_err" 2>/dev/null) || soif_sg_hdr_n=0
      soif_sg_hdr_n=$(printf '%s' "$soif_sg_hdr_n" | tr -d '[:space:]') || soif_sg_hdr_n=0
      case "$soif_sg_hdr_n" in ''|*[!0-9]*) soif_sg_hdr_n=0 ;; esac
      soif_sg_accepted=""
      if [ "$soif_sg_hdr_n" -eq 1 ]; then
        soif_sg_accepted=$(sed -n 's/^[[:space:]]*Scanning \([0-9][0-9]*\) files\{0,1\} with [0-9][0-9]* Code rules\{0,1\}:[[:space:]]*$/\1/p' "$soif_sg_err" 2>/dev/null) || soif_sg_accepted=""
      fi
      case "$soif_sg_accepted" in ''|*[!0-9]*) soif_sg_accepted="" ;; esac
      # BL-186-PARSE-COVERAGE (parse) — the SECOND half of the invariant, and the half the
      # counter above structurally cannot see: `Scanning N files` is fixed at TARGET
      # SELECTION time, so a target semgrep accepts and then fails to PARSE satisfies it
      # completely. Semgrep's `Parsed lines: ~N%` is the only number in the default banner
      # that reports parse loss. Rationale, the measured no-cry-wolf evidence, and the
      # residue this still does not catch are on # BL-112-SCAN-COVERAGE above.
      #   Same defensive shape as the header parse, deliberately, line for line: require
      #   the line EXACTLY ONCE, sanitize through a case-glob before any arithmetic, and
      #   guard every command with `|| …=""` so `set -e` cannot abort the hook here.
      #   NOT ANCHORED ON THE BULLET. The shipped line reads " • Parsed lines: ~100.0%".
      #   The bullet is multibyte UTF-8 and this file is sourced under `set -u` on hosts
      #   with a C locale, so it is matched by `.*` rather than embedded as a literal —
      #   a decorative glyph is not evidence and must not be load-bearing.
      #   NON-NUMERIC SPELLINGS FAIL CLOSED BY CONSTRUCTION. semgrep prints
      #   "an unknown percentage" when it counted zero lines and "<0.1%" for a near-total
      #   loss; neither matches the numeric pattern, so soif_sg_parsed stays EMPTY and the
      #   arm NOTRUNs. That is the right answer for both — one is unknown, one is a near
      #   total parse failure.
      soif_sg_parsed_n=$(grep -cE 'Parsed lines: ~?[0-9][0-9]*(\.[0-9][0-9]*)?%[[:space:]]*$' "$soif_sg_err" 2>/dev/null) || soif_sg_parsed_n=0
      soif_sg_parsed_n=$(printf '%s' "$soif_sg_parsed_n" | tr -d '[:space:]') || soif_sg_parsed_n=0
      case "$soif_sg_parsed_n" in ''|*[!0-9]*) soif_sg_parsed_n=0 ;; esac
      soif_sg_parsed=""
      if [ "$soif_sg_parsed_n" -eq 1 ]; then
        soif_sg_parsed=$(sed -n 's/^.*Parsed lines: ~\{0,1\}\([0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}\)%[[:space:]]*$/\1/p' "$soif_sg_err" 2>/dev/null) || soif_sg_parsed=""
      fi
      case "$soif_sg_parsed" in ''|*[!0-9.]*) soif_sg_parsed="" ;; esac
      # Compare on the INTEGER part only — bash 3.2 `test` has no floats, and it needs
      # none: semgrep CLAMPS any value above 99.9 down to 99.9 unless the numerator equals
      # the denominator exactly, so the integer part reaches 100 if and only if zero lines
      # were lost. `~99.9%` (whole=99) is a real shortfall, not a rounding artefact.
      soif_sg_parse_full=0
      soif_sg_parsed_whole="${soif_sg_parsed%%.*}"
      case "$soif_sg_parsed_whole" in
        ''|*[!0-9]*) soif_sg_parsed_whole="" ;;
      esac
      if [ -n "$soif_sg_parsed_whole" ] && [ "$soif_sg_parsed_whole" -ge 100 ]; then
        soif_sg_parse_full=1
      elif [ -z "$soif_sg_parsed" ]; then
        # # BL-186-EMPTY-TARGETS — THE VACUOUS CASE, AND IT IS CORROBORATED RATHER THAN
        # TRUSTED. semgrep's percentage is (total_lines - lines_it_failed_to_parse) /
        # total_lines, so when every target has ZERO lines the denominator is 0 and it
        # prints the literal words "an unknown percentage" instead of a number. That is
        # not a shortfall — nothing could have been lost — but the numeric parse above
        # cannot tell it apart from an output redesign, and without this arm the wholly
        # ordinary `touch src/placeholder.ts && git add && git commit` (a .gitkeep, an
        # empty __init__.py, a stub module) lost its receipt. That is the `Targets
        # scanned` cry-wolf failure all over again, so it is fixed rather than accepted.
        #   THE PHRASE IS NEVER WHAT BUYS THE RECEIPT. Matching semgrep's English would be
        #   a fail-OPEN string test — exactly the shape this arm refuses everywhere else —
        #   so the phrase is not matched at all. The condition is a fact this hook can
        #   check for itself: every target it materialized is zero bytes. If any target
        #   has content, an unreadable percentage stays unreadable and the arm NOTRUNs,
        #   whatever semgrep printed.
        #   WHY "ZERO BYTES ON DISK" IS SAFE TO BELIEVE HERE, and it is a COUPLING, not an
        #   assumption: the F2 content check a few lines up (soif_idx_want/soif_idx_got)
        #   already refuses to add a target whose materialized size differs from the staged
        #   blob's. So an empty target implies an empty STAGED BLOB; a truncated or failed
        #   materialization is recorded in soif_idx_unread and forfeits the receipt through
        #   # BL-182-NO-UNEARNED-RECEIPT before this code is reached. Weaken F2 and this
        #   arm's premise goes with it — T-mutation-content-guard is what pins the pair.
        soif_sg_all_empty=1
        for soif_e in ${soif_idx_files[@]+"${soif_idx_files[@]}"}; do
          if [ -s "$soif_e" ]; then soif_sg_all_empty=0; break; fi
        done
        if [ "$soif_sg_all_empty" -eq 1 ]; then soif_sg_parse_full=1; fi
      fi
      # BL-187-RULE-COVERAGE (parse) — THE THIRD FACT, AND THE ONE THE FIRST TWO
      # STRUCTURALLY CANNOT SEE. Selection is fixed before a byte is parsed; the parse
      # percentage is fixed once the AST exists. Neither is touched by what happens NEXT:
      # semgrep starts a rule against a target, hits its default 5-second per-rule timeout,
      # abandons that rule for that target, and reports a completed scan. Measured on
      # 1.157.0 through the shipped emitter (R-274Rv2-1): a dense 1,216,567-byte .ts with
      # `pane.innerHTML = userText` on line 2 gave `Scanning 1 file`, `Targets scanned: 1`,
      # `Parsed lines: ~100.0%`, rc=0 and the full [OK] receipt, while the ONE rule that
      # catches that sink was the rule that timed out.
      #   PRESENCE, NOT A NUMBER, AND THE ASYMMETRY IS DELIBERATE AND DOCUMENTED. The two
      #   halves above compare counts and fail closed on an unreadable line. This one asks
      #   whether a warning is THERE, so its good case is absence and "fail closed on
      #   absence" would NOTRUN every commit. See the FAIL CLOSED paragraph on
      #   # BL-112-SCAN-COVERAGE: this is a trigger detector, the residue is BL-187, and it
      #   must not be described as closing the class.
      #   MATCH THE ATOM, NOT THE SENTENCE — semgrep wraps the warning across two lines at
      #   ~120 columns even when stderr is a file, so `timeout error(s)` is the whole
      #   pattern. Same defensive plumbing as the other two: `|| …=0` so `set -e` cannot
      #   abort the hook, and a case-glob sanitize before the value reaches any arithmetic.
      #   A non-numeric or unreadable count sanitizes to 0, i.e. to "no timeout seen" —
      #   which is the fail-OPEN direction and is the honest consequence of a presence
      #   test, not an oversight. It is why this clause is a floor on the guarantee and not
      #   the guarantee itself.
      soif_sg_timeouts=$(grep -cE 'timeout error\(s\)' "$soif_sg_err" 2>/dev/null) || soif_sg_timeouts=0
      soif_sg_timeouts=$(printf '%s' "$soif_sg_timeouts" | tr -d '[:space:]') || soif_sg_timeouts=0
      case "$soif_sg_timeouts" in ''|*[!0-9]*) soif_sg_timeouts=0 ;; esac
      # `-ge`, not `-eq`: the defect class is UNDER-scanning. An over-count would be a
      # semgrep bug of a different shape and is not this guard's business to block on.
      # THE CONJUNCTION IS THE GUARD, AND IT IS THREE FACTS FOR THREE PIPELINE STAGES.
      # Selection alone is not coverage — that is what R-274Rv-1 proved — and selection
      # plus parse is not coverage either, which is what R-274Rv2-1 proved. Each clause is
      # mutation-tested on its own (T-mutation-scan-coverage owns selection,
      # T-mutation-parse-coverage parse, T-mutation-rule-timeout rule execution). Dropping
      # any one of the three must go RED.
      soif_sg_covered=0
      if [ -n "$soif_sg_accepted" ] && [ "$soif_sg_accepted" -ge "${#soif_idx_files[@]}" ] && [ "$soif_sg_parse_full" -eq 1 ] && [ "$soif_sg_timeouts" -eq 0 ]; then
        soif_sg_covered=1
      fi
      # Map the temp-tree prefix off finding paths, then show semgrep's findings
      # (stdout) with the real repo-relative paths. A clean scan prints nothing here.
      # The "[0-9][0-9]*/" arm strips the BL-178-PER-INDEX-DIR staged-position
      # segment too — without it the operator would be shown "3/src/app.ts", a path
      # that exists nowhere. Deeply-nested paths and paths CONTAINING SPACES round-
      # trip unchanged (only the leading tree+index prefix is removed).
      sed "s#${soif_idx_tree}/[0-9][0-9]*/##g" "$soif_sg_out"
      if [ "$soif_sg_rc" -eq 1 ]; then
        # 1 == semgrep found blocking findings (only ever returned with --error).
        echo ""
        echo "[BLOCKED] Semgrep detected security issues in staged files."
        echo "  Review and fix the ERROR-severity findings above before committing."
        # BL-182-PARTIAL-STILL-BLOCKS — a finding in the readable subset BLOCKS even
        # when coverage was partial. Under the old all-or-nothing `break` this commit
        # went NOTRUN and the sibling's vulnerability LANDED; blocking on what we DID
        # read is strictly safer. The operator is still shown the coverage gap, because
        # a blocked commit is exactly when they are about to re-stage and retry.
        if [ "${#soif_idx_unread[@]}" -gt 0 ]; then soif_sast_unread_report; fi
        # Same reasoning one layer out (# BL-112-SCAN-COVERAGE): a finding in what
        # semgrep DID accept still blocks, and the operator is still told that the scan
        # behind the block was incomplete — otherwise they fix the one reported finding
        # and re-commit believing the rest was checked.
        if [ "$soif_sg_covered" -ne 1 ]; then soif_sast_scan_coverage_report; fi
        FAILED=1
        soif_ledger_blocked semgrep || true   # BL-163-BLOCKED-LEDGER
      elif [ "$soif_sg_rc" -ne 0 ]; then
        # >=2 == semgrep ITSELF failed (invalid/missing config, registry
        # unreachable, unparseable rule). BL-112-SAST-NOTRUN arm 2 of 2: the scanner
        # did not run. DECLARED DECISION — this WARNs, it does not block; see the
        # rationale on soif_sast_not_enforced above. It is treated identically to
        # the absent arm because it IS the absent arm wearing a different coat. And
        # it SURFACES the diagnostic: an operator who cannot see why the scanner
        # died cannot fix it, and a gate you cannot fix is a gate you route around.
        soif_sast_not_enforced "semgrep could not complete (exit $soif_sg_rc) — the tool itself failed."
        if [ "${#soif_idx_unread[@]}" -gt 0 ]; then soif_sast_unread_report; fi
        sed 's/^/  /' "$soif_sg_err" >&2
      elif [ "${#soif_idx_unread[@]}" -gt 0 ]; then
        # BL-182-NO-UNEARNED-RECEIPT — the scan RAN and came back clean, but it did not
        # see everything that is being committed. A clean SUBSET is not a clean COMMIT:
        # printing the [OK] receipt here would be precisely the BL-112 lie this whole
        # arm exists to prevent, merely scoped to part of a commit instead of all of
        # it — and the entry we could not read is exactly where a sink would hide.
        # Route to the loud partial report and name what was missed.
        # TWO COUNTS, NO DENOMINATOR — deliberately. "N of M staged entries" would be
        # wrong the moment a gitlink is also staged: a gitlink is neither scanned nor
        # unreadable (it is not content), so it belongs to neither count and any total
        # that implies otherwise is a small lie in a message whose whole job is not to
        # tell them. Report what WAS scanned and what could NOT be read; the list that
        # follows names the second group exactly.
        soif_sast_partial_coverage "SAST coverage was PARTIAL: ${#soif_idx_files[@]} staged file(s) scanned clean, ${#soif_idx_unread[@]} could NOT be read (listed below)."
        soif_sast_unread_report
        # Both gaps can hold at once (an unreadable entry AND a target semgrep declined),
        # and they are different facts about different entries. Report both; suppressing
        # the second because the first already forfeited the receipt would leave the
        # operator fixing one gap and re-committing into the other.
        if [ "$soif_sg_covered" -ne 1 ]; then soif_sast_scan_coverage_report; fi
      elif [ "$soif_sg_covered" -ne 1 ]; then
        # BL-112-SCAN-COVERAGE (verdict) — the scan RAN, exited 0, every staged entry was
        # READ, and semgrep still did not take everything it was handed. Structurally this
        # is # BL-182-NO-UNEARNED-RECEIPT one layer further out: BL-182 guards the entries
        # the LOOP could not read, this guards the targets the SCANNER did not accept. The
        # [OK] receipt is forfeited either way, because the sentence it prints — "SAST ran
        # on N staged file(s)" — would be false.
        # FIVE SUB-ARMS, because these are five different claims and must not share
        # wording. Two axes: WHICH third of the invariant failed (selection, parse —
        # # BL-186-PARSE-COVERAGE — or rule execution, # BL-187-RULE-COVERAGE), and
        # whether the failure is a MEASURED shortfall or an UNVERIFIABLE reading. Calling
        # an unreadable line "partial" would assert a fact not in evidence; telling an
        # operator "semgrep skipped a file" when what actually happened is "semgrep could
        # not parse the file it did open" — or "semgrep read every line and then gave up on
        # a rule" — sends them to fix the wrong thing. All are the small dishonesty this
        # whole arm exists to avoid. Ordered so the EARLIER pipeline stage is reported
        # first: a selection shortfall makes the parse percentage a statement about a
        # subset, and a parse shortfall makes the rule result a statement about a subset,
        # so it would be misleading to lead with either.
        #   THE LAST ARM IS AN `else` AND THAT IS LOAD-BEARING, NOT LAZINESS. Reaching this
        #   block means soif_sg_covered is 0; the four tests above cover every way the
        #   selection and parse clauses can fail; so the residue is exactly the timeout
        #   clause. An `elif` on the timeout count would leave a silent no-output arm if a
        #   FOURTH clause is ever added — which is the BL-179 `-gt 0` with no `else` defect
        #   verbatim. Whoever adds a fourth clause must add its arm ABOVE this `else`.
        if [ -z "$soif_sg_accepted" ]; then
          soif_sast_coverage_warn \
            "semgrep exited 0, but its scan-status line was absent or unreadable." \
            "the scan ran and its coverage of this commit CANNOT BE VERIFIED, so it is treated as a scan that did not run."
        elif [ "$soif_sg_accepted" -lt "${#soif_idx_files[@]}" ]; then
          soif_sast_coverage_warn \
            "SAST coverage was PARTIAL: semgrep accepted only $soif_sg_accepted of the ${#soif_idx_files[@]} staged file(s) it was handed." \
            "at least one staged file was handed to the scanner and never opened by it."
        elif [ -z "$soif_sg_parsed" ]; then
          soif_sast_coverage_warn \
            "semgrep exited 0 and took every staged file, but its parse-coverage line was absent or unreadable." \
            "how much of the staged content the scanner actually parsed CANNOT BE VERIFIED, so it is treated as a scan that did not run."
        elif [ "$soif_sg_parse_full" -ne 1 ]; then
          soif_sast_coverage_warn \
            "SAST coverage was PARTIAL: semgrep took every staged file but parsed only ${soif_sg_parsed}% of their lines." \
            "the unparsed lines were never matched against any rule, so a sink sitting on one of them would not have been reported."
        else
          soif_sast_coverage_warn \
            "SAST coverage was PARTIAL: semgrep read every staged file in full, then ABANDONED at least one rule on its per-rule timeout (${soif_sg_timeouts} warning(s))." \
            "a rule that ran out of time never finished matching, so a sink only that rule detects would not have been reported."
        fi
        soif_sast_scan_coverage_report
      else
        # 0 == the scan RAN and found nothing at ERROR severity. SAY SO. A gate that
        # is silent when it passes is indistinguishable from a gate that never ran —
        # which is the entire BL-112 defect class. This receipt is what makes the
        # clean-commit test falsifiable: without it, "a clean file commits" is also
        # true on a host where the scanner was simply skipped, and the test would
        # pass vacuously while proving nothing.
        # The count is the number of files ACTUALLY TARGETED (${#soif_idx_files[@]}),
        # not the number staged: since BL-132-GITLINK-SKIP the two can differ, and a
        # receipt that counts entries the scanner never saw is the BL-112 lie in a
        # different coat. Zero targets never reaches here — it NOTRUNs above.
        # Reached ONLY with COMPLETE coverage. FIVE things have to hold for that, and
        # they are enforced in five different places — a reader checking this claim must
        # check ALL FIVE. Each was added only after a false [OK] shipped without it:
        #   1. every entry the loop was GIVEN was read — the branch above intercepts any
        #      commit with a non-empty soif_idx_unread;
        #   2. the loop was given every staged entry that HAS content —
        #      # BL-179-STAGED-FILTER. A letter missing from that filter truncates the
        #      TARGET SET before the loop runs, so soif_idx_unread is empty, the guard
        #      above cannot fire, and N is silently a count of a subset. That is exactly
        #      how a staged TYPE CHANGE bought a false [OK] while the filter was ACMR
        #      (R-WPC-1). The filter and this receipt are one contract, not two;
        #   3. semgrep ACCEPTED every target the loop handed it — # BL-112-SCAN-COVERAGE.
        #      Preconditions 1 and 2 are both about what reaches the SCANNER; neither can
        #      see the scanner quietly dropping a target it was given, which is what a
        #      >1MB staged blob did under the default --max-target-bytes (R-274R-1);
        #   4. semgrep PARSED every line of what it accepted — # BL-186-PARSE-COVERAGE.
        #      Preconditions 1-3 are ALL target-selection facts and none of them can see a
        #      file semgrep took and then could not read: an ordinary .ts saved as UTF-16
        #      satisfied all three and collected this receipt with its innerHTML sink
        #      never looked at (R-274Rv-1);
        #   5. no rule was ABANDONED part-way — # BL-187-RULE-COVERAGE. Preconditions 1-4
        #      are all fixed before or at parse time and none of them can see semgrep
        #      giving up on a rule afterwards: a dense 1.2MB .ts satisfied all four
        #      (`Scanning 1 file`, `Targets scanned: 1`, `Parsed lines: ~100.0%`, rc=0) and
        #      collected this receipt while the one rule that catches its line-2 innerHTML
        #      sink hit semgrep's 5-second per-rule timeout (R-274Rv2-1).
        # The pattern across all five is the same and is the point: N counts the targets
        # this arm INTENDED to scan, and every stage between "staged entry" and "a rule
        # finished matching" needs its own proof that nothing fell out of the set. It is
        # also why this list is not a closure claim — see the RESIDUE paragraph on
        # # BL-112-SCAN-COVERAGE, BL-186 and BL-187. A SIXTH precondition will exist one
        # day; the previous revision of this line predicted a fifth and was right within
        # one review round.
        echo "[OK] semgrep: SAST ran on ${#soif_idx_files[@]} staged file(s) — no ERROR-severity findings."
      fi
    fi
    rm -rf "$soif_idx_tree"
    rm -f "$soif_sg_err" "$soif_sg_out"
  else
    # BL-179-EMPTY-STAGED — this `else` is the second half of BL-179 and it exists to
    # END A SILENCE. Before it, zero staged targets meant zero OUTPUT: the operator was
    # told nothing at all, which is indistinguishable from a clean scan and is the exact
    # BL-112 dishonesty class this arm was built to close. With R and T now in the filter
    # the residual shape here is a commit with no scannable content of its own — a pure
    # DELETION — and it still deserves a receipt saying so. (A TYPE CHANGE is emphatically
    # NOT such a shape: it is a staged blob with real content and it belongs in the SCAN,
    # not in this else — see the T paragraph of # BL-179-STAGED-FILTER.) Deliberately
    # the same loud NOTRUN as every other can't-scan path: "the scanner had nothing to
    # look at" and "the scanner could not look" are the same fact to a reader deciding
    # whether this commit was checked.
    soif_sast_not_enforced "no scannable staged file content (nothing added, copied, modified, renamed or type-changed) — SAST skipped."
  fi
else
  # BL-112-SAST-NOTRUN arm 1 of 2 — the documented semgrep-absent contract: WARN,
  # never block. Pinned in both directions (absent => the commit LANDS; invert the
  # arm to block => the contract test goes RED).
  soif_sast_not_enforced "semgrep not found — pre-commit SAST skipped."
  echo "  Install: brew install semgrep (macOS) or pip install semgrep"
fi

HOOKEOF

  # BL-125-TEST-EXEC-BEGIN
  # Emitter fence: excising this region removes the commit-time test arm from
  # every hook this lib emits (the suite's mutation case pins exactly that).
  # The EMITTED bytes carry their own marker, # BL-125-COMMIT-TESTS, kept
  # distinct from this fence so in-hook greps and emitter excision never
  # collide.
  cat <<'TESTEOF'

# --- Project Test Execution (BL-125) ---
# BL-125-COMMIT-TESTS — Dogfood-2 F-DF2-009: a commit landed while `npm test`
# was 5 failed | 54 passed; the failing tests were the adversarial fixtures
# PROVING the staged code was an exploitable XSS. The one control that
# actually saw the code run was consulted by no gate. This arm runs the
# project's test command at commit time, under the SAST arm's honesty
# contract (# BL-112-SAST-NOTRUN): not-runnable => LOUD skip, never a silent
# pass; a suite that RAN and failed => BLOCK. rc=127 (runner not found) is
# the one reliably tool-shaped exit and takes the not-runnable arm; every
# other non-zero exit blocks — an ERRORING suite is not a passing suite.
#   Resolution order: .claude/test-command (first line, operator-owned; set
#   it to your fast lane if the full suite is slow) -> detected stack
#   default (package.json real test script / pytest / cargo / go) -> loud
#   not-enforced WARN.
#   Fast lane (latency discipline): the arm runs only when STAGED files
#   include source (added/copied/modified/DELETED/RENAMED); docs/config-only
#   commits skip with a receipt.
#   DECLARED (verifier S5): a DETECTED suite that runs and reports "no
#   tests collected" (pytest rc=5, jest no-tests rc=1) BLOCKS — this repo's
#   methodology is tests-first, so a source commit with a detected-but-
#   empty suite is off-loop by definition; the escapes are honest and
#   printed (write the first test, or point .claude/test-command at your
#   lane).
soif_tests_not_enforced() {
  echo ""
  echo "[WARN] $1"
  echo "  PROJECT TESTS NOT ENFORCED for this commit — the suite did not run."
  echo "  This is NOT a green result: nothing was executed. Configure the"
  echo "  command in .claude/test-command (one line, e.g. 'npm test')."
}
# BL-179-TESTARM-FILTER — Verifier M1: D, R and T are in the filter ON
# PURPOSE — a commit that DELETES, RENAMES or TYPE-CHANGES the sanitizer
# is exactly the regression this arm exists to stop, and the old ACM
# filter skipped it while printing the "no source files staged" receipt
# (a false receipt — the dishonesty class this arm fights).
#   T (TYPE CHANGE) IS IN FOR THE SAME REASON D AND R ARE: a type change
#   is a REAL STAGED BLOB of source, and de-symlinking a file (symlink ->
#   regular file, index mode 100644) is an ordinary refactor, not an
#   exotic shape. While this read was ACMDR such a commit was invisible
#   here: the suite never ran and the arm printed
#   `[OK] BL-125: no source files staged — project tests not required for
#   this commit.` over a staged source change — verbatim the failure the
#   comment above says this filter exists to stop (R-274R-2, reproduced
#   through the real emitter with an always-failing test command: control
#   `M src/real.ts` -> REFUSED with the suite running; `T src/lib.ts` ->
#   COMMITTED, suite never ran; same staged index, `ACMDR` sees [] and
#   `ACMDRT` sees [src/lib.ts]).
#   THIS FILTER IS STILL NOT THE SAST ARM'S. That one is ACMRT and
#   deliberately EXCLUDES D (# BL-179-STAGED-FILTER): it must SCAN
#   CONTENT and a deleted path has none. This arm must RUN THE TESTS, and
#   a deletion is precisely when they must run. The two agree on T and
#   disagree on D for reasons specific to each; do not sync them by
#   copying.
# .mts/.cts are first-class typescript.
soif_test_src=$(git diff --cached --name-only --diff-filter=ACMDRT \
  | grep -cE '\.(ts|tsx|mts|cts|js|jsx|mjs|cjs|py|rb|go|rs|java|kt|kts|swift|cs|dart|c|h|cc|cpp|hpp|php|scala|vue|svelte)$') || soif_test_src=0
case "$soif_test_src" in ''|*[!0-9]*) soif_test_src=0 ;; esac
if [ "$soif_test_src" -gt 0 ]; then
  soif_test_cmd=""
  soif_test_cfg_warned=0
  if [ -e .claude/test-command ]; then
    # The config file is operator-owned: once it exists, IT resolves the
    # command — no detect fallback (a broken config falling back to a
    # different suite would run something the operator did not choose).
    # Verifier M2/S2/S6: first non-blank, non-comment line, CRLF-stripped
    # and trimmed; empty/unreadable/comment-only files take the LOUD arm —
    # `sh -c '   '` and `sh -c '# npm test'` both exit 0, and certifying a
    # no-op as "[OK] PASSED" is worse than the silent pass this arm ends.
    if [ -r .claude/test-command ] && [ -s .claude/test-command ]; then
      soif_test_cmd=$(tr -d '\r' < .claude/test-command | grep -vE '^[[:space:]]*(#|$)' | head -1) || soif_test_cmd=""
      soif_test_cmd=$(printf '%s' "$soif_test_cmd" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi
    if [ -z "$soif_test_cmd" ]; then
      soif_tests_not_enforced "'.claude/test-command' exists but holds no runnable command (empty, unreadable, or only blank/comment lines)."
      soif_test_cfg_warned=1
    fi
  elif [ -f package.json ] \
       && sed -n '/"scripts"[[:space:]]*:/,/}/p' package.json | grep -qE '"test"[[:space:]]*:' \
       && ! sed -n '/"scripts"[[:space:]]*:/,/}/p' package.json | grep -q 'no test specified'; then
    # npm's scaffold placeholder script is `echo "Error: no test specified"
    # && exit 1` — treating it as a real suite would brick every commit on a
    # fresh scaffold (the BL-137 documented-but-impossible class). Verifier
    # S1/S4: BOTH greps are scoped to the "scripts" block, so a dependency
    # literally named "test" cannot trigger detection and a placeholder
    # string elsewhere in package.json cannot disable a real suite.
    soif_test_cmd="npm test"
  elif [ -f pytest.ini ] || [ -f conftest.py ] \
       || { [ -f pyproject.toml ] && grep -q '^\[tool\.pytest' pyproject.toml; }; then
    soif_test_cmd="pytest"
  elif [ -f Cargo.toml ]; then
    soif_test_cmd="cargo test"
  elif [ -f go.mod ]; then
    soif_test_cmd="go test ./..."
  fi
  if [ -z "$soif_test_cmd" ]; then
    if [ "$soif_test_cfg_warned" -eq 0 ]; then
      soif_tests_not_enforced "no test command configured or detected for this project."
    fi
  else
    echo ""
    echo "[..] BL-125: running project tests: $soif_test_cmd"
    set +e
    sh -c "$soif_test_cmd" </dev/null
    soif_test_rc=$?
    set -e
    if [ "$soif_test_rc" -eq 0 ]; then
      # The receipt makes the clean-commit case falsifiable — a silent pass
      # is indistinguishable from an arm that never ran (the BL-112 class).
      echo "[OK] project tests: '$soif_test_cmd' PASSED — commit may proceed."
    elif [ "$soif_test_rc" -eq 127 ]; then
      soif_tests_not_enforced "'$soif_test_cmd' is not runnable here (exit 127 — runner not found)."
    else
      echo ""
      echo "[BLOCKED] project tests FAILED (exit $soif_test_rc): $soif_test_cmd"
      echo "  A commit whose own tests are RED cannot land (BL-125). The tests"
      echo "  are the one control that actually sees the code run — fix the"
      echo "  failures, or fix the tests if they are wrong. Slow suite? Point"
      echo "  .claude/test-command at your fast lane."
      FAILED=1
      soif_ledger_blocked bl125_tests || true   # BL-163-BLOCKED-LEDGER
    fi
  fi
else
  echo "[OK] BL-125: no source files staged — project tests not required for this commit."
fi
TESTEOF
  # BL-125-TEST-EXEC-END

  # Section 2 (was TDDEOF).
  cat <<'TDDEOF'

# --- TDD Ordering Gate (BL-072) ---
# Tier-keyed test-first enforcement runs at COMMIT-MSG time (see
# .git/hooks/commit-msg), not here: a pre-commit hook cannot see the commit
# message the gate scopes on (git writes it after pre-commit runs).
TDDEOF

  # Section 3 (was SCHEMAEOF).
  cat <<'SCHEMAEOF'

# --- Schema Migration Check ---
# Warns when schema files are edited directly instead of through migrations (Phase 2+).
PHASE_STATE=".claude/phase-state.json"
CURRENT_PHASE=0
if [ -f "$PHASE_STATE" ]; then
  CURRENT_PHASE=$(grep -o '"current_phase"[[:space:]]*:[[:space:]]*"*[0-9][0-9]*"*' \
    "$PHASE_STATE" | grep -o '[0-9][0-9]*' || echo "0")
  # Sanitize: multi-match (e.g. duplicate current_phase keys in a
  # hand-edited file) yields a multi-line value like "2\n3" — the
  # subsequent `[ "$CURRENT_PHASE" -ge 2 ]` then errors with
  # "integer expression expected" and silently flips the gate.
  # Collapse any non-numeric / multi-token result to 0 (safe default).
  # Same pattern as scripts/check-phase-gate.sh (PR #53).
  case "$CURRENT_PHASE" in ''|*[!0-9]*) CURRENT_PHASE=0 ;; esac
fi

if [ "$CURRENT_PHASE" -ge 2 ]; then
  SCHEMA_PATTERNS='(schema\.prisma|schema\.sql|schema\.rb|models\.py|\.schema\.ts|\.entity\.ts|schema\.graphql)$'
  staged_schema=$(git diff --cached --name-only --diff-filter=ACM \
    | grep -E "$SCHEMA_PATTERNS" \
    | grep -vE '(migrations?/|migrate/)' \
    || true)

  if [ -n "$staged_schema" ]; then
    echo ""
    echo "[WARN] Direct schema file changes detected (Phase $CURRENT_PHASE):"
    echo "$staged_schema" | sed 's/^/  /'
    echo ""
    echo "  The Solo Orchestrator methodology requires data model changes"
    echo "  through versioned migrations, not direct schema edits."
    echo "  If this is intentional (e.g., Prisma schema before migration gen),"
    echo "  this warning can be ignored."
    echo "  (This is a warning — commit is not blocked.)"
  fi
fi
SCHEMAEOF

  # Section 4 (was EXITEOF). The close marker is the region's final line.
  #
  # BL-112 (walk finding F8): this section used to be an UNCONDITIONAL
  # `exit $FAILED`. scripts/install-filesystem-gates.sh appends the BL-030
  # strict-mode gate block (`# >>> SOIF framework gate (BL-030)` … which runs
  # .git/hooks/framework-gate.sh -> process-checklist.sh --check-commit-ready)
  # BELOW this managed region — so the unconditional exit made that whole block
  # UNREACHABLE DEAD CODE. Net effect: the phase2-init-verified, UAT-in-progress
  # and build-loop-state gates had NO git-hook backstop and fired only through
  # the AI-session PreToolUse hook; a human/terminal `git commit` walked straight
  # through all three. The exit is now CONDITIONAL, which is the whole fix:
  # the appended gate block is the surviving path and it runs.
  #
  # Exit contract (unchanged): any failing arm above => non-zero exit; every arm
  # clean => fall through to the strict gate, which exits non-zero iff IT blocks.
  # If the gate block is absent (light / no enforcement, or gate uninstalled) the
  # hook ends here and the false `if` yields status 0.
  #
  # The region boundary is deliberate: the gate block must stay OUTSIDE the
  # markers so BL-099's region refresh (_bl099_replace_region) can rewrite the
  # fallback without clobbering the independently-managed gate block.
  cat <<'EXITEOF'

# --- Terminal exit / hand-off to the BL-030 strict gate ---
# BL-112-STRICT-GATE: this exit is CONDITIONAL ON PURPOSE. install-filesystem-gates.sh
# appends its strict-gate marker block BELOW this region, so an unconditional
# `exit $FAILED` here turns that block into unreachable dead code and the gate
# never runs. See scripts/lib/hook-templates.sh. Do not "simplify" it back.
if [ "$FAILED" -ne 0 ]; then
  exit "$FAILED"
fi
# <<< SOIF pre-commit fallback
EXITEOF
}

# soif_write_precommit_hook <file>
#   Writes the complete fallback pre-commit hook to <file> (shebang on line 1,
#   then the managed region) and chmod +x's it. The sync path uses
#   soif_precommit_region_body directly to refresh just the managed region of an
#   already-marked hook, preserving anything the operator (or
#   install-filesystem-gates.sh) put outside the markers.
soif_write_precommit_hook() {
  local hook="$1"
  printf '%s\n' '#!/usr/bin/env bash' > "$hook"
  soif_precommit_region_body >> "$hook"
  chmod +x "$hook"
}

# ── Commit-msg BL-072 TDD gate block ────────────────────────────────────────
# soif_tdd_region_body — the managed region ONLY (open marker … close marker),
#   no leading blank line. Used for stale-comparison and in-place refresh.
#   BL-171: the region now also embeds the shared soif_ledger_blocked helper and
#   a # BL-171-COMMITMSG-LEDGER block that records a terminal_commit_blocked row
#   when a message gate refuses (commitmsg_tdd / commitmsg_buildloop). The
#   refusal itself (the plain non-zero -> exit 1) sits OUTSIDE that block so a
#   fence excision drops the telemetry only, never the block.
soif_tdd_region_body() {
  echo "$SOIF_TDD_OPEN"
  echo '# Two message-scoped commit-msg gates run here (--terminal-mode --tdd-only):'
  echo '#  1. Tier-keyed test-first enforcement (BL-072 Phase C2): sponsored-POC /'
  echo '#     production -> HARD BLOCK when a feat/fix/refactor commit ships'
  echo '#     implementation with no accompanying test; personal / private-POC ->'
  echo '#     logged WARNING (bypassable). Escape: SOLO_TDD_ATTESTED=1 (recorded to'
  echo '#     .claude/process-state.json::tdd_attestations[]).'
  echo '#  2. BL-006 Build-Loop commit-message check (BL-010): a feat: commit in'
  echo '#     Phase 2+ requires an active, sufficiently-complete Build Loop. This'
  echo '#     surface reaches editor-opened / human-terminal commits the AI-only'
  echo '#     PreToolUse hook cannot see.'
  echo 'if [ -x scripts/pre-commit-gate.sh ]; then'
  echo '  # BL-171: --emit-blocked-gate makes a genuine refusal exit 3 (BL-072'
  echo '  # TDD-ordering block) or 4 (BL-006 Build-Loop block); any other non-zero'
  echo '  # is some other refusal. WARN-tier / attested / allowed outcomes exit 0.'
  echo '  # BL-171 (verifier MAJOR): capture the rc via `|| soif_cm_rc=$?`, NOT a'
  echo '  # bare call + `$?`. When this region is composed onto a user hook whose'
  echo '  # preamble runs `set -e` (the common case — init.sh/verify-install/'
  echo '  # upgrade-project APPEND it to pre-existing hooks), a bare non-zero call'
  echo '  # would abort the shell at this line before `$?` is read: the commit is'
  echo '  # still refused but the ledger row silently vanishes — the very loss'
  echo '  # BL-171 closes. The `||` consumes the non-zero so `set -e` never fires.'
  echo '  soif_cm_rc=0'
  echo '  scripts/pre-commit-gate.sh --terminal-mode --tdd-only --emit-blocked-gate || soif_cm_rc=$?'
  # BL-171-LEDGER-EMIT-BEGIN
  # Emitter fence (template-only, NOT emitted). The helper BYTES are the shared
  # BL-163 source (soif_emit_ledger_helper); it is injected OUTSIDE the emitted
  # # BL-171-COMMITMSG-LEDGER range on purpose, so this fence governs only the
  # commit-msg CALL SITES while a helper-body excision stays BL-163's concern.
  soif_emit_ledger_helper
  cat <<'CMGATEEOF'
# BL-171-COMMITMSG-LEDGER-BEGIN
# BL-171-COMMITMSG-LEDGER — Dogfood-4 F-DF4-009 residual (named by the BL-163
# verifier): the message-scoped commit-msg gates refuse a commit by exiting this
# hook non-zero BEFORE .git/hooks/framework-gate.sh runs — so, exactly like
# BL-163's pre-commit arms, a genuine refusal here left NO terminal_commit_blocked
# row in .claude/bypass-audit.json. The gate's --emit-blocked-gate codes name
# which gate refused; record the matching row best-effort. soif_ledger_blocked is
# non-fatal and subshell-confined, so a broken/trojan ledger lib can never launder
# the refusal. Excising this BEGIN..END block drops the TELEMETRY ONLY — the
# refusal below (the plain non-zero -> exit 1) is untouched.
  if [ "$soif_cm_rc" -eq 3 ]; then
    soif_ledger_blocked commitmsg_tdd || true          # BL-171-COMMITMSG-LEDGER
  elif [ "$soif_cm_rc" -eq 4 ]; then
    soif_ledger_blocked commitmsg_buildloop || true    # BL-171-COMMITMSG-LEDGER
  fi
# BL-171-COMMITMSG-LEDGER-END
CMGATEEOF
  # BL-171-LEDGER-EMIT-END
  echo '  if [ "$soif_cm_rc" -ne 0 ]; then'
  echo '    exit 1'
  echo '  fi'
  echo 'fi'
  echo "$SOIF_TDD_CLOSE"
}

# soif_emit_tdd_commitmsg_block — the exact bytes init.sh appends to an existing
#   commit-msg hook: a leading blank line, then the managed region. Preserved
#   byte-for-byte from init.sh's pre-refactor inline `{ echo ""; echo ...; }`.
soif_emit_tdd_commitmsg_block() {
  echo ""
  soif_tdd_region_body
}

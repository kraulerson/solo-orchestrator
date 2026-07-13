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
#     unknown), which is the gate init.sh uses to decide whether to install the
#     commit-msg TDD hook at all.
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
# languages have none). init.sh installs the commit-msg TDD hook iff this is
# non-empty — replicated by the sync path so rust/unknown are EXPECTED to lack
# the hook (no prompt, no install).
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

# ── Fallback pre-commit hook ────────────────────────────────────────────────
# soif_precommit_region_body
#   Emits the managed region ONLY: the open marker, the hook body, and the close
#   marker — everything EXCEPT the shebang (which must stay file line 1, outside
#   the region). Used both to write a fresh hook and to refresh the region of an
#   already-marked hook in place. Byte-identical to init.sh's pre-BL-099 hook
#   APART FROM the two marker lines.
soif_precommit_region_body() {
  # Section 1 (was HOOKEOF, minus shebang). Open marker is the region's 1st line.
  cat <<'HOOKEOF'
# >>> SOIF pre-commit fallback
# Solo Orchestrator — Fallback Pre-Commit Hook
# Provides baseline enforcement: secret detection + SAST + test co-location check.
# If Development Guardrails for Claude Code is active, its hooks provide deeper coverage.

set -euo pipefail

FAILED=0

# --- Secret Detection (gitleaks) ---
if command -v gitleaks &>/dev/null; then
  if ! gitleaks git --staged 2>/dev/null; then
    echo ""
    echo "[BLOCKED] gitleaks detected secrets in staged files."
    echo "  Remove the secrets, use environment variables or a secrets manager,"
    echo "  and rotate any credentials that were exposed."
    FAILED=1
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

if command -v semgrep &>/dev/null; then
  # Scan only staged files for fast pre-commit feedback.
  #
  # NUL-delimited read into an array rather than `| xargs -0 semgrep …`: xargs
  # COLLAPSES the utility's exit code (BSD xargs -> 1, GNU xargs -> 123 for ANY
  # non-zero), which makes semgrep's "blocking findings" code (1) indistinguish-
  # able from a semgrep TOOL failure (>=2: bad config, registry unreachable,
  # parse error). The two must be told apart — one blocks, the other warns.
  soif_staged=()
  while IFS= read -r -d '' soif_f; do
    soif_staged+=("$soif_f")
  done < <(git diff --cached --name-only --diff-filter=ACM -z)

  if [ "${#soif_staged[@]}" -gt 0 ]; then
    # semgrep splits its output cleanly: FINDINGS go to stdout, the scan banner
    # AND its fatal errors go to stderr. So we capture stderr rather than send it
    # to /dev/null: on the happy path it is progress noise we drop (which is all
    # `--quiet` ever bought us), and on a tool failure it is the ONLY place the
    # real diagnostic appears — `--quiet` suppresses even that, which is why the
    # flag is gone. Findings stay on stdout and are always shown.
    soif_sg_err="$(mktemp)"
    set +e
    # BL-112-SAST-ERROR — `--error` is LOAD-BEARING. Semgrep exits 0 even when it
    # finds (and prints!) issues unless --error is passed, so without it the
    # [BLOCKED] arm below is UNREACHABLE and an `eval(req.query.code)` Express RCE
    # is detected, printed, and committed clean (E2E walk finding F9).
    # `--severity=ERROR` bounds the gate to semgrep's high-confidence rules: the
    # gate must block real issues without becoming so noisy that operators route
    # around it. WARNING/INFO findings still surface in the Phase-3 scanners + CI.
    semgrep scan --config=p/owasp-top-ten --no-git-ignore \
      --severity=ERROR --error "${soif_staged[@]}" 2>"$soif_sg_err"
    soif_sg_rc=$?
    set -e
    if [ "$soif_sg_rc" -eq 1 ]; then
      # 1 == semgrep found blocking findings (only ever returned with --error).
      echo ""
      echo "[BLOCKED] Semgrep detected security issues in staged files."
      echo "  Review and fix the ERROR-severity findings above before committing."
      FAILED=1
    elif [ "$soif_sg_rc" -ne 0 ]; then
      # >=2 == semgrep ITSELF failed (invalid config, registry unreachable,
      # unparseable rule). BL-112-SAST-NOTRUN arm 2 of 2: the scanner did not run.
      # DECLARED DECISION — this WARNs, it does not block; see the rationale on
      # soif_sast_not_enforced above. It is treated identically to the absent arm
      # because it IS the absent arm wearing a different coat. And it SURFACES the
      # diagnostic: an operator who cannot see why the scanner died cannot fix it,
      # and a gate you cannot fix is a gate you route around.
      soif_sast_not_enforced "semgrep could not complete (exit $soif_sg_rc) — the tool itself failed."
      sed 's/^/  /' "$soif_sg_err" >&2
    else
      # 0 == the scan RAN and found nothing at ERROR severity. SAY SO. A gate that
      # is silent when it passes is indistinguishable from a gate that never ran —
      # which is the entire BL-112 defect class. This receipt is what makes the
      # clean-commit test falsifiable: without it, "a clean file commits" is also
      # true on a host where the scanner was simply skipped, and the test would
      # pass vacuously while proving nothing.
      echo "[OK] semgrep: SAST ran on ${#soif_staged[@]} staged file(s) — no ERROR-severity findings."
    fi
    rm -f "$soif_sg_err"
  fi
else
  # BL-112-SAST-NOTRUN arm 1 of 2 — the documented semgrep-absent contract: WARN,
  # never block. Pinned in both directions (absent => the commit LANDS; invert the
  # arm to block => the contract test goes RED).
  soif_sast_not_enforced "semgrep not found — pre-commit SAST skipped."
  echo "  Install: brew install semgrep (macOS) or pip install semgrep"
fi

HOOKEOF

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
  echo '  scripts/pre-commit-gate.sh --terminal-mode --tdd-only || exit 1'
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

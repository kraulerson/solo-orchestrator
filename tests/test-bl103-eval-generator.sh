#!/usr/bin/env bash
# tests/test-bl103-eval-generator.sh
#
# BL-103 regression: the six-eval generator that the Phase 3→4 review gate
# (BL-073) tells the operator to run — evaluation-prompts/Projects/run-reviews.sh
# — was DEAD ON ARRIVAL on the reference platform (bash 3.2), and even once it
# parsed it recorded the mandatory Red Team review as MISSING.
#
# THE TWO DEFECTS PINNED HERE
#   Defect 1 (portability). run-reviews.sh / compose.sh (Projects) and
#     run-reviews.sh (Framework) used `declare -A` and `[[ -v x ]]` — bash >= 4.2
#     only. On /bin/bash 3.2.57 (the repo's reference platform, and the shell the
#     gate's remediation line runs under) `bash -n` is a SYNTAX ERROR:
#       run-reviews.sh: line 142: syntax error near `"REVIEWERS[$num]"'
#     The gate FAILs the project and hands the operator a script that cannot run.
#
#   Defect 2 (slug↔filename drift). The manifest generator probed
#     "$PROJECT_DIR/${reviewer}-review-v1.md" using its OWN reviewer slug
#     (engineer|cio|security|legal|techuser|redteam), but the base prompts tell
#     the reviewer to write senior-engineer-review-v1.md /
#     technical-user-review-v1.md / red-team-review-v1.md. Three of six slugs
#     never resolved — including REDTEAM, a MANDATORY BLOCKING reviewer. A
#     project that ran the Red Team review and saved it exactly as instructed
#     still got a manifest with no Red Team entry, and the gate FAILed.
#
#   Why it shipped green: tests/test-bl073-review-manifest-gate.sh builds its
#   manifest with a `write_manifest` heredoc and NEVER runs the generator
#   (fixture-hides-product-gap). This suite runs the real generator.
#
# THE FIX (single source of truth)
#   The BASE PROMPT declares the artifact filename (`<name>-review-v1.md`), and
#   it is the ONLY place that does. compose.sh --artifact <reviewer> DERIVES it
#   by parsing that declaration; run-reviews.sh probes the derived name. There is
#   no second table to drift from — a prompt that changes its declared filename
#   moves the runner with it, and a prompt with zero or >1 declarations is a hard
#   ERROR, not a silent miss.
#
# TESTS
#   T-portability          every evaluation-prompts/**/*.sh passes `/bin/bash -n`
#                          (RED on main: three files are syntax errors).
#   T-generator-runs       run the REAL run-reviews.sh against a hermetic fixture
#                          project with a mock `claude` on PATH → it produces
#                          docs/eval-results/review-manifest.json.
#   T-manifest-lints       the emitted manifest passes scripts/lint-review-manifest.sh.
#   T-redteam-recorded     a red-team-review-v1.md written exactly as the prompt
#                          instructs MUST land in the manifest as a "redteam"
#                          role under check-phase-gate.sh's own role mapping
#                          (RED on main: never emitted).
#   T-slug-filename-parity every base prompt declares exactly ONE artifact and
#                          `compose.sh --artifact <slug>` resolves to it — RED if
#                          any slug drifts from its prompt.
#   T-lint-clean           scripts/lint-evalprompts-portability.sh passes on the
#                          real tree.
#   T-mutation-portability plant `declare -A` in a SCRATCH COPY of the tree → the
#                          lint goes RED; restore → GREEN. Proves the lint's
#                          check is load-bearing (not a tautological grep).
#
# bash-3.2 safe: no associative arrays, no mapfile, no ${var^^}.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EVAL_ROOT="$REPO_ROOT/evaluation-prompts"
PROJ_PROMPTS="$EVAL_ROOT/Projects"
MANIFEST_LINT="$REPO_ROOT/scripts/lint-review-manifest.sh"
PORT_LINT="$REPO_ROOT/scripts/lint-evalprompts-portability.sh"
GATE="$REPO_ROOT/scripts/check-phase-gate.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# The six reviewer slugs the runner dispatches on, and the artifact each base
# prompt DECLARES. This table exists ONLY inside the test: it is the independent
# oracle the product must agree with. If the product ever grows a second table
# of its own, T-slug-filename-parity is what catches the drift.
SLUGS="engineer cio security legal techuser redteam"
expected_artifact() {
  case "$1" in
    engineer) echo "senior-engineer-review-v1.md" ;;
    cio)      echo "cio-review-v1.md" ;;
    security) echo "security-review-v1.md" ;;
    legal)    echo "legal-review-v1.md" ;;
    techuser) echo "technical-user-review-v1.md" ;;
    redteam)  echo "red-team-review-v1.md" ;;
    *)        return 1 ;;
  esac
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-portability: every evaluation-prompts/**/*.sh parses under /bin/bash 3.2 ==="
# ════════════════════════════════════════════════════════════════════
# /bin/bash on the reference host IS 3.2.57 — it is the oracle, not a proxy.
port_bad=""
port_n=0
while IFS= read -r sh; do
  [ -n "$sh" ] || continue
  port_n=$((port_n + 1))
  if ! /bin/bash -n "$sh" 2>/dev/null; then
    port_bad="$port_bad $(basename "$(dirname "$sh")")/$(basename "$sh")"
  fi
done <<EOF
$(find "$EVAL_ROOT" -name '*.sh' -type f | sort)
EOF

if [ "$port_n" -eq 0 ]; then
  fail_ "T-portability" "found no *.sh under evaluation-prompts/ — the scan is vacuous"
elif [ -z "$port_bad" ]; then
  pass "T-portability: all $port_n evaluation-prompts scripts parse under /bin/bash ($(/bin/bash --version | head -1 | sed 's/.*version //;s/ .*//'))"
else
  fail_ "T-portability" "these scripts are syntax errors under /bin/bash 3.2:$port_bad
  (bash >= 4.2 constructs — declare -A / [[ -v x ]] — are banned; see CLAUDE.md)"
fi

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-slug-filename-parity: each base prompt declares ONE artifact; compose.sh derives it ==="
# ════════════════════════════════════════════════════════════════════
# Part 1 — every base prompt declares exactly one `<name>-review-v1.md`.
# A prompt with zero declarations gives the runner nothing to derive from;
# a prompt with two makes the derivation ambiguous. Both are drift vectors.
for base in "$PROJ_PROMPTS"/bases/*.md; do
  [ -f "$base" ] || continue
  decls=$(grep -o '`[A-Za-z0-9_.-]*-review-v1\.md`' "$base" 2>/dev/null | tr -d '`' | sort -u)
  n=$(printf '%s' "$decls" | grep -c . 2>/dev/null || echo "0")
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  if [ "$n" -eq 1 ]; then
    pass "T-slug-filename-parity: $(basename "$base") declares exactly one artifact ($decls)"
  else
    fail_ "T-slug-filename-parity" "$(basename "$base") declares $n artifact filenames (expected exactly 1): $decls"
  fi
done

# Part 2 — compose.sh --artifact <slug> resolves to that declaration, for all six.
for slug in $SLUGS; do
  want=$(expected_artifact "$slug")
  got=$(bash "$PROJ_PROMPTS/compose.sh" --artifact "$slug" 2>/dev/null)
  if [ "$got" = "$want" ]; then
    pass "T-slug-filename-parity: compose.sh --artifact $slug → $got"
  else
    fail_ "T-slug-filename-parity" "compose.sh --artifact $slug → '${got:-<none>}', expected '$want' (slug↔filename drift: this is Defect 2)"
  fi
done

# Part 3 — the derivation must REFUSE an unknown reviewer rather than invent one.
if bash "$PROJ_PROMPTS/compose.sh" --artifact bogus >/dev/null 2>&1; then
  fail_ "T-slug-filename-parity" "compose.sh --artifact bogus exited 0 — an unknown reviewer must be a hard error, not a silent empty artifact"
else
  pass "T-slug-filename-parity: compose.sh --artifact bogus is a hard error (no silent fallback)"
fi

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-generator-runs / T-manifest-lints / T-redteam-recorded ==="
# ════════════════════════════════════════════════════════════════════
# Hermetic end-to-end: a scratch COPY of evaluation-prompts/Projects (so the run
# never touches the repo tree), a mock `claude` on PATH that honours the prompt's
# OWN declared filename, and a throwaway project dir. Nothing leaves the tmpdir;
# no network, no real AI invocation.
TMP=$(mktemp -d)
cleanup() { rm -rf "$TMP"; }

MOCK="$TMP/bin"
mkdir -p "$MOCK"
# The mock reviewer does exactly what the base prompt tells a real reviewer to
# do: extract the declared output filename from the prompt it was handed and
# write the review there, in the CWD (the project root). If the runner and the
# prompt ever disagree about the filename, the manifest misses the review —
# which is precisely the bug this reproduces.
cat > "$MOCK/claude" <<'MOCKEOF'
#!/bin/bash
prompt=""
while [ $# -gt 0 ]; do
  case "$1" in
    -p) prompt="${2:-}"; shift 2 ;;
    *)  shift ;;
  esac
done
out=$(printf '%s\n' "$prompt" | grep -o '`[A-Za-z0-9_.-]*-review-v1\.md`' | tr -d '`' | head -1)
if [ -z "$out" ]; then
  echo "mock-claude: prompt declared no output filename" >&2
  exit 1
fi
printf '# Mock review\n\nHermetic stand-in output. No findings.\n' > "$out"
echo "mock-claude: wrote $out"
MOCKEOF
chmod +x "$MOCK/claude"

PROMPTS_COPY="$TMP/Projects"
cp -R "$PROJ_PROMPTS" "$PROMPTS_COPY"
chmod +x "$PROMPTS_COPY/run-reviews.sh" "$PROMPTS_COPY/compose.sh" 2>/dev/null || true

FIXPROJ="$TMP/proj"
mkdir -p "$FIXPROJ"

gen_rc=0
gen_out=$(PATH="$MOCK:$PATH" PROJECT_DIR="$FIXPROJ" bash "$PROMPTS_COPY/run-reviews.sh" web-app 2>&1) || gen_rc=$?

MANIFEST="$FIXPROJ/docs/eval-results/review-manifest.json"

if [ "$gen_rc" -eq 0 ]; then
  pass "T-generator-runs: run-reviews.sh web-app completed (rc=0) against the hermetic fixture"
else
  fail_ "T-generator-runs" "run-reviews.sh exited rc=$gen_rc; out:
$gen_out"
fi

if [ -f "$MANIFEST" ]; then
  pass "T-generator-runs: emitted docs/eval-results/review-manifest.json"
else
  fail_ "T-generator-runs" "no manifest at docs/eval-results/review-manifest.json; out:
$gen_out"
fi

# Every one of the six review files the prompts declare must exist after the run.
missing_files=""
for slug in $SLUGS; do
  want=$(expected_artifact "$slug")
  [ -f "$FIXPROJ/$want" ] || missing_files="$missing_files $want"
done
if [ -z "$missing_files" ]; then
  pass "T-generator-runs: all six declared review files written to the project root"
else
  fail_ "T-generator-runs" "review files missing after the run:$missing_files"
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "  [SKIP] jq not available — manifest-content assertions skipped."
else
  # T-manifest-lints — the generator's own output must satisfy the BL-073 schema.
  if [ -f "$MANIFEST" ] && bash "$MANIFEST_LINT" --file "$MANIFEST" >/dev/null 2>&1; then
    pass "T-manifest-lints: generator output passes scripts/lint-review-manifest.sh"
  else
    fail_ "T-manifest-lints" "the emitted manifest fails the schema lint:
$(bash "$MANIFEST_LINT" --file "$MANIFEST" 2>&1 || true)"
  fi

  # All six reviewers must be RECORDED — not just the three whose slug happened
  # to equal their filename stem.
  entry_count=$(jq '[ .reviews[]? ] | length' "$MANIFEST" 2>/dev/null || echo "0")
  case "$entry_count" in ''|*[!0-9]*) entry_count=0 ;; esac
  if [ "$entry_count" -eq 6 ]; then
    pass "T-generator-runs: manifest records all 6 reviews (entry_count=$entry_count)"
  else
    fail_ "T-generator-runs" "manifest records $entry_count review(s), expected 6 — a slug whose filename never resolved is silently dropped (Defect 2)"
  fi

  # T-redteam-recorded — the load-bearing one. Resolve the manifest through
  # check-phase-gate.sh's OWN role mapping (kept verbatim in sync with the gate's
  # jq below) so this test agrees with the gate by construction, not by luck.
  roles=$(jq -r '
    [ .reviews[]?
      | select((.status // "complete") == "complete")
      | ((.reviewer // "") | ascii_downcase) as $r
      | if   ($r | test("red[ ._-]?team|offensive")) then "redteam"
        elif ($r | test("security"))                  then "security"
        elif ($r | test("engineer"))                  then "engineer"
        elif ($r | test("cio|chief information"))      then "cio"
        elif ($r | test("legal|counsel"))             then "legal"
        elif ($r | test("techuser|technical user|non.?coder")) then "techuser"
        else empty end
    ] | unique | join(" ")
  ' "$MANIFEST" 2>/dev/null || echo "")

  case " $roles " in
    *" redteam "*)
      pass "T-redteam-recorded: red-team-review-v1.md → manifest entry resolving to role 'redteam'" ;;
    *)
      fail_ "T-redteam-recorded" "the Red Team review was performed and saved as red-team-review-v1.md, yet the manifest records no redteam role (roles: '${roles:-<none>}'). The gate's MANDATORY BLOCKING reviewer is invisible — this is the BL-103 headline." ;;
  esac
  case " $roles " in
    *" security "*)
      pass "T-redteam-recorded: security role also present (the other mandatory reviewer)" ;;
    *)
      fail_ "T-redteam-recorded" "no security role in the manifest (roles: '${roles:-<none>}')" ;;
  esac

  # And the artifact field must name the file that actually exists on disk.
  bad_artifacts=""
  while IFS= read -r art; do
    [ -n "$art" ] || continue
    [ -f "$FIXPROJ/$art" ] || bad_artifacts="$bad_artifacts $art"
  done <<EOF
$(jq -r '.reviews[]?.artifact // empty' "$MANIFEST" 2>/dev/null)
EOF
  if [ -z "$bad_artifacts" ]; then
    pass "T-redteam-recorded: every manifest artifact path resolves to a real file"
  else
    fail_ "T-redteam-recorded" "manifest names artifacts that do not exist:$bad_artifacts"
  fi

  # The gate's role mapping must actually be the one we replicated above. If the
  # gate is retuned, this fails loudly instead of letting the two drift apart.
  if grep -qF 'red[ ._-]?team|offensive' "$GATE" 2>/dev/null; then
    pass "T-redteam-recorded: check-phase-gate.sh still uses the replicated role regex"
  else
    fail_ "T-redteam-recorded" "check-phase-gate.sh's redteam role regex changed — re-sync this test's jq mapping with the gate's"
  fi
fi

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-lint-clean: scripts/lint-evalprompts-portability.sh passes on the real tree ==="
# ════════════════════════════════════════════════════════════════════
if [ ! -f "$PORT_LINT" ]; then
  fail_ "T-lint-clean" "scripts/lint-evalprompts-portability.sh does not exist"
else
  lrc=0
  lout=$(bash "$PORT_LINT" 2>&1) || lrc=$?
  if [ "$lrc" -eq 0 ]; then
    pass "T-lint-clean: the portability lint is green on evaluation-prompts/"
  else
    fail_ "T-lint-clean" "lint rc=$lrc:
$lout"
  fi
fi

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-mutation-portability: plant a bash-4 construct in a SCRATCH tree → lint RED ==="
# ════════════════════════════════════════════════════════════════════
# The lint is attacked at its BEHAVIOUR (does a real bash-4-ism get caught?),
# not by grepping it for a marker — a marker-grep would be tautological.
if [ ! -f "$PORT_LINT" ]; then
  fail_ "T-mutation-portability" "lint missing — cannot mutation-test"
else
  MUTROOT="$TMP/mutroot"
  mkdir -p "$MUTROOT"
  cp -R "$EVAL_ROOT" "$MUTROOT/evaluation-prompts"

  # Control: the scratch copy of the (fixed) tree must be GREEN.
  crc=0
  bash "$PORT_LINT" --root "$MUTROOT" >/dev/null 2>&1 || crc=$?
  if [ "$crc" -eq 0 ]; then
    pass "T-mutation-portability: control — unmutated scratch copy is GREEN"
  else
    fail_ "T-mutation-portability" "control failed: unmutated scratch copy is already RED (rc=$crc)"
  fi

  VICTIM="$MUTROOT/evaluation-prompts/Projects/compose.sh"

  # Mutation A — reintroduce `declare -A` (the banned associative array).
  cp "$VICTIM" "$TMP/victim.bak"
  printf '\ndeclare -A MUTANT_MAP\nMUTANT_MAP[x]="y"\n' >> "$VICTIM"
  mrc=0
  bash "$PORT_LINT" --root "$MUTROOT" >/dev/null 2>&1 || mrc=$?
  if [ "$mrc" -ne 0 ]; then
    pass "T-mutation-portability: planted 'declare -A' → lint RED (rc=$mrc)"
  else
    fail_ "T-mutation-portability" "planted 'declare -A' but the lint stayed GREEN — the check is not load-bearing"
  fi
  cp "$TMP/victim.bak" "$VICTIM"

  # Mutation B — reintroduce `[[ -v x ]]` (the banned -v test).
  printf '\nif [[ -v MUTANT_VAR ]]; then :; fi\n' >> "$VICTIM"
  mrc=0
  bash "$PORT_LINT" --root "$MUTROOT" >/dev/null 2>&1 || mrc=$?
  if [ "$mrc" -ne 0 ]; then
    pass "T-mutation-portability: planted '[[ -v x ]]' → lint RED (rc=$mrc)"
  else
    fail_ "T-mutation-portability" "planted '[[ -v x ]]' but the lint stayed GREEN — the check is not load-bearing"
  fi
  cp "$TMP/victim.bak" "$VICTIM"

  # Mutation C — a raw SYNTAX error the `bash -n` arm must catch even though the
  # two construct greps cannot (proves the parse check is independently
  # load-bearing). A dangling `fi` is a parse error in every bash.
  printf '\nfi\n' >> "$VICTIM"
  mrc=0
  bash "$PORT_LINT" --root "$MUTROOT" >/dev/null 2>&1 || mrc=$?
  if [ "$mrc" -ne 0 ]; then
    pass "T-mutation-portability: planted a syntax error → lint RED (rc=$mrc) via the bash -n arm"
  else
    fail_ "T-mutation-portability" "planted a syntax error but the lint stayed GREEN — the bash -n arm is not load-bearing"
  fi
  cp "$TMP/victim.bak" "$VICTIM"

  # Restore → GREEN.
  rrc=0
  bash "$PORT_LINT" --root "$MUTROOT" >/dev/null 2>&1 || rrc=$?
  if [ "$rrc" -eq 0 ]; then
    pass "T-mutation-portability: restored → lint GREEN again (RED↔GREEN under our control)"
  else
    fail_ "T-mutation-portability" "restore failed: lint still RED (rc=$rrc)"
  fi
fi

cleanup

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0

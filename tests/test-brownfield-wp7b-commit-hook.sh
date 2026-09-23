#!/usr/bin/env bash
# tests/test-brownfield-wp7b-commit-hook.sh — WP7/3: the commit-time scanners on
# the adoption path.
#
# SPEC: docs/designs/2026-08-23-brownfield-adoption-v2.md §10-WP7 ("the fallback
# pre-commit hook install, now that the artifacts it reads exist" — and its
# stated proof obligation: "The hook installed on a completed fixture admits a
# compliant commit and blocks a non-compliant one BY EXIT CODE") and §7.1 (the
# archive-and-replace population, which includes every non-`.sample` file in
# `.git/hooks/`). Backlog: `## BL-242:`.
#
# ─────────────────────────────────────────────────────────────────────────────
# WHY THIS SUITE RUNS REAL ADOPTIONS AND IS SLOW.
#
# The claim under test is about what `git commit` does inside a project this
# framework has just adopted. Every cheap way of asking that question — grep the
# installer, source the emitter, inspect the hook text — answers a different
# question, and the one that mattered was answered wrongly for a whole work
# package: `adopt_stub_hooks` said installing the hook "refuses every commit",
# which WAS true when measured and had stopped being true by the time WP7/1
# landed the Adoption Record. Nobody re-measured it because nothing executed it.
#
# So: two real adoptions, and then real commits with real exit codes.
#
# ─────────────────────────────────────────────────────────────────────────────
# WHAT EACH CASE OWNS.
#   B1-B2  the DOM-sink ruleset is installed and committed, and an adoptee's own
#          copy is not overwritten
#   B3     the hook comes from the SHARED emitter, not a third spelling
#   B4-B6  the proof obligation: admits compliant, blocks non-compliant, by rc
#   B7     the SAST arm actually RUNS (this is what B1 buys, and the reason B1
#          exists at all)
#   B8     §7.1: the operator's own hook is replaced, disclosed, and its archive
#          row says `replaced` rather than `kept`
#   B9     the stub is retired, not merely silent
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

echo "== WP7/3 — the commit-time scanners on the adoption path =="

for t in git jq; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done

WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK"' EXIT

# _adoptee DIR [OWNHOOK] — a small real project with its own history.
_adoptee() {
  local p="$1" own="${2:-}"
  mkdir -p "$p/src" "$p/docs" || return 1
  ( cd "$p" && git init -q . \
      && git config user.email wp7b@test.invalid \
      && git config user.name "WP7b Test" ) >/dev/null 2>&1 || return 1
  printf '{"name":"acme","scripts":{"test":"exit 0"}}\n' > "$p/package.json"
  printf '# acme\n' > "$p/README.md"
  printf '# Purpose\n\nInvoice reconciliation.\n' > "$p/docs/product.md"
  if [ -n "$own" ]; then
    mkdir -p "$p/.git/hooks"
    # A MARKER THEIR HOOK ALONE CARRIES. A first cut wrote `exit 0` and then
    # asserted the hook was gone by grepping for `exit 0` — which the
    # framework's own 1700-line hook also contains, so the case reported the
    # replacement as not having happened while it had.
    printf '#!/bin/sh\n# THEIR-OWN-PRE-COMMIT-MARKER\nexit 0\n' > "$p/.git/hooks/pre-commit"
    chmod +x "$p/.git/hooks/pre-commit"
  fi
  # `--no-verify` HERE ONLY, and only because the fixture plants a hook of its
  # own in the line above: this commit is the ADOPTEE's pre-existing history,
  # not something the framework authored, and their hook is irrelevant to it.
  ( cd "$p" && git add package.json README.md docs/product.md \
      && git commit -q --no-verify -m "chore: their own history" ) >/dev/null 2>&1 || return 1
  return 0
}

# _adopt DIR — run a real adoption. Sets ADOPT_RC, and leaves the transcript at
# $WORK/<name>.out so a case can assert on what the operator was told.
_adopt() {
  local p="$1" tag="$2"
  printf '2\n1\n1\n1\n1\n' > "$WORK/ans"
  ( cd "$p" && bash "$REPO_ROOT/scripts/adopt-project.sh" \
      --scan-report "$WORK/scan/scout-report.json" < "$WORK/ans" ) \
    > "$WORK/$tag.out" 2> "$WORK/$tag.err"
  ADOPT_RC=$?
}

# One Scout report, produced by the real scanner against a template adoptee.
if ! _adoptee "$WORK/template" || \
   ! bash "$REPO_ROOT/scripts/scout.sh" --root "$WORK/template" --out "$WORK/scan" >/dev/null 2>&1 || \
   [ ! -s "$WORK/scan/scout-report.json" ]; then
  skip "every case" "scripts/scout.sh produced no report; adoption consumes one and cannot be tested without it"
  echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0
fi

# ── The two adoptions every case below reads ────────────────────────────────
P1="$WORK/plain"; P2="$WORK/ownhook"
_adoptee "$P1" || { fail_ "setup" "could not build the plain adoptee"; }
_adoptee "$P2" own || { fail_ "setup" "could not build the own-hook adoptee"; }
_adopt "$P1" plain;   RC1="$ADOPT_RC"
_adopt "$P2" ownhook; RC2="$ADOPT_RC"
[ "$RC1" -eq 0 ] || fail_ "setup" "the plain adoption did not complete (rc $RC1): $(tail -3 "$WORK/plain.err")"
[ "$RC2" -eq 0 ] || fail_ "setup" "the own-hook adoption did not complete (rc $RC2): $(tail -3 "$WORK/ownhook.err")"

# _commit DIR MSG FILE CONTENT — stage one file and commit. Echoes the rc.
_commit() {
  local p="$1" msg="$2" f="$3"
  ( cd "$p" && git add "$f" && git commit -m "$msg" ) > "$WORK/commit.out" 2>&1
  printf '%s' "$?"
}

# ═══════════════════════════════════════════════════════════════════════════
b1() {
  local label="B1 the DOM-sink ruleset is installed AND committed"
  local bad=""
  [ -f "$P1/.semgrep/soif-dom-sinks.yml" ] || bad="$bad [.semgrep/soif-dom-sinks.yml is not on disk]"
  ( cd "$P1" && git ls-tree -r --name-only HEAD | grep -qx '.semgrep/soif-dom-sinks.yml' ) \
    || bad="$bad [it is not in the adoption commit — CI checks out the committed tree]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

b2() {
  local label="B2 an adoptee's own .semgrep ruleset is NOT overwritten"
  local p="$WORK/ownsem" bad=""
  _adoptee "$p" || { fail_ "$label" "could not build the adoptee"; return; }
  mkdir -p "$p/.semgrep"
  printf '# THEIR OWN RULES\nrules: []\n' > "$p/.semgrep/soif-dom-sinks.yml"
  ( cd "$p" && git add .semgrep/soif-dom-sinks.yml && git commit -q --no-verify -m "chore: our rules" ) >/dev/null 2>&1
  _adopt "$p" ownsem
  [ "$ADOPT_RC" -eq 0 ] || bad="$bad [the adoption did not complete (rc $ADOPT_RC)]"
  grep -q 'THEIR OWN RULES' "$p/.semgrep/soif-dom-sinks.yml" \
    || bad="$bad [their ruleset was overwritten — the hook reads that path either way, so theirs should stand]"
  grep -q 'You already have .semgrep/soif-dom-sinks.yml' "$WORK/ownsem.out" \
    || bad="$bad [the run never said it left their ruleset alone]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

b3() {
  local label="B3 the installed hook is the SHARED emitter's, not a third spelling"
  local ref="$WORK/reference-hook" bad=""
  ( set +u; . "$REPO_ROOT/scripts/lib/hook-templates.sh"; soif_write_precommit_hook "$ref" ) >/dev/null 2>&1 \
    || { fail_ "$label" "the shared emitter would not run"; return; }
  [ -x "$P1/.git/hooks/pre-commit" ] || bad="$bad [no executable pre-commit hook in the adopted project]"
  # BYTE-IDENTICAL. A hand-written adoption-side copy is how this repo's own
  # hook became a silent stale version (`# BL-243-HOOK-TEMPLATE`), so equality
  # with the one owner is the property, not "it mentions gitleaks".
  if [ -f "$P1/.git/hooks/pre-commit" ] && ! cmp -s "$ref" "$P1/.git/hooks/pre-commit"; then
    bad="$bad [the adopted hook differs from soif_write_precommit_hook's output — a second spelling has appeared]"
  fi
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

b4() {
  local label="B4 a compliant commit LANDS in an adopted project (rc 0)"
  local rc
  printf '# A note\n\nText.\n' > "$P1/docs/note.md"
  rc="$(_commit "$P1" "docs: add a note" docs/note.md)"
  if [ "$rc" = "0" ]; then
    pass "$label"
  else
    fail_ "$label" "rc=$rc — the hook refuses an ordinary commit, which is the state that deferred it for a whole work package: $(grep -E 'BLOCKED|FAIL' "$WORK/commit.out" | head -2)"
  fi
}

b5() {
  local label="B5 a commit whose project tests FAIL is blocked (rc 1)"
  local rc
  # The fixture's `npm test` is `exit 0`; make it fail for this commit only.
  ( cd "$P1" && jq '.scripts.test = "exit 1"' package.json > package.json.tmp && mv package.json.tmp package.json )
  printf 'export function add(a,b){return a+b}\n' > "$P1/src/add.js"
  rc="$(_commit "$P1" "feat: add" src/add.js)"
  ( cd "$P1" && jq '.scripts.test = "exit 0"' package.json > package.json.tmp && mv package.json.tmp package.json )
  if [ "$rc" != "0" ] && grep -q 'BLOCKED' "$WORK/commit.out"; then
    pass "$label (rc=$rc)"
  else
    fail_ "$label" "rc=$rc and no [BLOCKED] line — the commit-time test arm is not running"
  fi
  ( cd "$P1" && git reset -q HEAD src/add.js 2>/dev/null; rm -f src/add.js )
}

b6() {
  local label="B6 a staged private key is blocked (rc 1)"
  local rc
  # THE KEY IS ASSEMBLED AT RUNTIME, NEVER SPELLED IN THIS FILE. The first
  # draft wrote the BEGIN/END lines literally, and the REPO'S OWN pre-commit hook
  # refused to commit this suite (`RuleID: private-key`, this file) — the check
  # this case exists to prove, catching the case's own source. It was right to:
  # a key-shaped literal in committed source is exactly what it is for. Split
  # across adjacent quoted strings (`'PRIV''ATE'`), the file never contains the
  # contiguous pattern and the runtime value still does — the same idiom as
  # `HOOK_PLANT` in tests/test-brownfield-wp6-collision-archive.sh.
  { printf -- '-----BEGIN RSA PRIV''ATE KEY-----\n'
    printf 'MIIEowIBAAKCAQEAwJ8vX2kQ7mZs9fL3nR5tYpB1cD4eF6gH8iJ0kL2mN4oP6qR8s\n'
    printf -- '-----END RSA PRIV''ATE KEY-----\n'; } > "$P1/deploy.pem"
  rc="$(_commit "$P1" "chore: key" deploy.pem)"
  if ! command -v gitleaks >/dev/null 2>&1; then
    skip "$label" "gitleaks is not on PATH; the hook WARNs and does not block, which is its documented behaviour"
  elif [ "$rc" != "0" ] && grep -qi 'gitleaks detected secrets' "$WORK/commit.out"; then
    pass "$label (rc=$rc)"
  else
    fail_ "$label" "rc=$rc — a private key reached a commit in a project this framework just adopted"
  fi
  ( cd "$P1" && git reset -q HEAD deploy.pem 2>/dev/null; rm -f deploy.pem )
}

b7() {
  local label="B7 the static-analysis arm RUNS rather than warning that it did not"
  # THIS IS WHAT B1 BUYS. Without the ruleset the hook passes
  # `--config=.semgrep/soif-dom-sinks.yml` at a path that is not there, semgrep
  # exits 7, and every commit in the adopted project prints "SAST NOT ENFORCED
  # for this commit — the scanner did not run". Measured before WP7/3 shipped.
  if ! command -v semgrep >/dev/null 2>&1; then
    skip "$label" "semgrep is not on PATH; its absence is its own WARN arm and not this case's subject"
    return
  fi
  printf '# Another note\n' > "$P1/docs/note2.md"
  _commit "$P1" "docs: another note" docs/note2.md >/dev/null
  if grep -q 'SAST NOT ENFORCED' "$WORK/commit.out"; then
    fail_ "$label" "the scanner did not run: $(grep -A1 'SAST NOT ENFORCED' "$WORK/commit.out" | tail -1)"
  else
    pass "$label"
  fi
}

b8() {
  local label="B8 the operator's own hook is replaced, disclosed, and recorded as replaced"
  local bad="" dispo
  grep -q 'REPLACED by the framework' "$WORK/ownhook.out" \
    || bad="$bad [the run never told them their hook was replaced]"
  grep -q 'THEIR-OWN-PRE-COMMIT-MARKER' "$P2/.git/hooks/pre-commit" 2>/dev/null \
    && bad="$bad [their hook is still at the path — it was not replaced]"
  # …and the archived copy must be THEIRS, not a copy of the framework's.
  grep -rq 'THEIR-OWN-PRE-COMMIT-MARKER' "$P2/.claude/adoption-archive/" 2>/dev/null \
    || bad="$bad [the archive does not contain their hook's bytes — the restore line would put back the wrong file]"
  # ARCHIVED, and the row must say what really happened to it. `kept` means
  # "the operator's original is still at the path", which is now false.
  dispo="$( cd "$P2" && jq -r '[.entries[]|select(.originalPath==".git/hooks/pre-commit")|.disposition]|first // "MISSING"' \
            .claude/adoption-archive/*/MANIFEST.json 2>/dev/null )"
  [ "$dispo" = "replaced" ] || bad="$bad [the archive row says '$dispo', not 'replaced' — the record an auditor reads would be wrong]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

b9() {
  local label="B9 the commit-time-scanner stub is retired, not merely silent"
  local bad="" called f
  grep -q 'NOT DONE — the commit-time scanners' "$WORK/plain.out" \
    && bad="$bad [the run still announces the scanners as NOT DONE]"
  grep -q 'adopt_stub_hooks()' "$REPO_ROOT/scripts/lib/adopt/adopt-stubs.sh" \
    && bad="$bad [adopt_stub_hooks is still defined — the stub outlived the thing it stood for]"
  # And the derived set, which is `## BL-242:`'s own recipe for what is unbuilt.
  # NO `case` INSIDE `$( )`. The outer shell parses the substitution first and
  # ends it at the pattern's `)`, reporting a syntax error on a later line that
  # is perfectly well formed — measured twice in this repo while writing tests.
  # `grep -v` does the same exclusion with no metacharacter.
  ls "$REPO_ROOT"/scripts/adopt-project.sh "$REPO_ROOT"/scripts/lib/adopt/*.sh \
    | grep -v 'adopt-stubs\.sh$' > "$WORK/stubsrc"
  : > "$WORK/stubstrip"
  while IFS= read -r f; do
    [ -n "$f" ] && sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#.*$//' "$f" >> "$WORK/stubstrip"
  done < "$WORK/stubsrc"
  called="$(grep -ohE '\badopt_stub_[a-z_]+' "$WORK/stubstrip" | LC_ALL=C sort -u | grep -c .)"
  [ "$called" -eq 4 ] || bad="$bad [the called-stub set is $called, not 4 — re-derive it and update this case deliberately]"
  [ -z "$bad" ] && pass "$label (4 stubs still called)" || fail_ "$label" "$bad"
}

b1; b2; b3; b4; b5; b6; b7; b8; b9

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]

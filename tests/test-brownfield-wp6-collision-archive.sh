#!/usr/bin/env bash
# tests/test-brownfield-wp6-collision-archive.sh — behaviour suite for the
# collision archive, its MANIFEST, the disclosure, the re-add warning and its
# audit row, and §7.3's archive-secrets refusal (WP6-brownfield).
#
# SPEC: docs/designs/2026-08-02-brownfield-adoption-v1.md — §7.1 (the four
# buckets), §7.2 (archive layout and MANIFEST, and the five properties
# inherited from `_upgrade_snapshot_pre_mutation`), §7.3 (disclosure, the
# re-add warning, and THE NEW EXPOSURE: archiving a `.git/hooks/` file promotes
# an UNTRACKED file into version control), §8.9 (the `adoption_event` row and
# the five surfaces a new row type touches), §10-WP6, §12-5.
#
# ─────────────────────────────────────────────────────────────────────────────
# WHAT THIS SUITE IS PROTECTING, IN ONE SENTENCE
#
# The archive collects files the operator wrote — hooks, AI settings, MCP
# connections — and stages them into a commit, so a credential that was
# UNTRACKED or GITIGNORED before adoption can be committed BY adoption. §7.3
# says the driver must scan the archive before staging and refuse a matching
# entry, and this suite proves the refusal with a real planted key.
#
# ─────────────────────────────────────────────────────────────────────────────
# THE PLANT, AND WHY IT IS SHAPED THE WAY IT IS (§6.5's fixture preconditions,
# applied to a different surface)
#
#   HOOK_PLANT  AKIA3XN7QW5ZTBMR2VKD  — in the fixture's .git/hooks/pre-commit.
#
# It matches `AKIA[A-Z2-7]{16}`. BASE32-VALIDITY IS LOAD-BEARING: the
# `aws-access-token` rule requires the 16 characters after `AKIA` to be drawn
# from [A-Z2-7], so a plant containing a `9` or a `1` yields ZERO findings and
# every assertion below passes for the wrong reason. `AKIAIOSFODNN7EXAMPLE` is
# separately allowlisted by gitleaks' own default config and also yields zero.
# S0 therefore asserts a NON-ZERO finding count AND that the probe can see the
# plant in the archive copy BEFORE any absence is asserted — a dud fixture
# fails loudly instead of certifying nothing.
#
# `.git/hooks/pre-commit` is the right carrier and not an arbitrary one: git
# never tracks `.git/`, so the plant is provably absent from the adoptee's
# history before adoption runs. Any occurrence in the commit is one THIS
# DESIGN created.
#
# EVERY ABSENCE ASSERTION HAS A POSITIVE CONTROL. The archive's copy of the
# hook is the operator's own file and MUST contain the plant — that is what an
# archive is. So the probe is proven able to see the plant (S0, exactly one
# occurrence in the archive copy) before it is used to assert zero occurrences
# in the MANIFEST, the transcript, the ledger and the committed tree. The
# committed-tree probe gets its own control too: `git grep` over HEAD must find
# a token that IS committed, or "found nothing" would mean "looked at nothing".
#
# ─────────────────────────────────────────────────────────────────────────────
# THE MUTATIONS
#
#   S4  neuter the pre-staging scan (ONE marked line)  -> the secret-bearing
#                                                         archive entry is
#                                                         COMMITTED and the
#                                                         plant is in the
#                                                         committed tree -> RED
#   R2  neuter the re-add audit row (ONE marked line)  -> the file is still
#                                                         restored and NO row
#                                                         is written: a SILENT
#                                                         re-add -> RED
#   E6  neuter the emitter's type literal              -> the REAL T6 predicate,
#                                                         extracted from
#                                                         tests/test-bl029-integration.sh,
#                                                         rejects the ledger -> RED
#
# R2 asserts the file bytes as well as the row count, because a mutant that
# died before doing anything leaves the same "no row" state a correct refusal
# does. E6 exists because §8.9's own indictment of the two previous row types
# is that their pins run over fixture ledgers that never contain them — a
# whitelist entry with no fixture exercising it is a pin that cannot go red.
#
# EXIT CODES AND VALUES, NEVER LABELS (CLAUDE.md's [WARN] trap).
#
# GITLEAKS IS DETECTED, NEVER ASSUMED, and a skip is LOUD — and FATAL in CI.
# The posture is WP2's, for WP2's reason: a green required check credited with
# a leak proof that never ran is the silent-success class sitting on the
# highest-stakes property in this design. The workflows install a pinned,
# checksum-verified gitleaks in every unit shard, so this arm fires only if
# that install is removed or breaks.
#
# HERMETICITY: every fixture is a `mktemp -d` tree; no network, no real remote.
# bash-3.2 safe: no associative arrays, no `${var,,}`, no `mapfile`, no
# `((x++))`.
#
# LANE: registered in tests/full-project-test-suite.sh AND in the
# .github/workflows/tests.yml `unit-shard` list. `mk_mirror` NAMES init.sh on
# an executed line (the driver derives the shipped-script set from init.sh's
# own copy list, so a mutation mirror must carry it), which makes this suite
# unit-lane-EXEMPT by `# BL-181-UNIT-LANE-PREDICATE`. It is registered in the
# unit list anyway — the suite never runs the scaffolder, and the lint says an
# exempted file that is in the list anyway "decided nothing and is not
# rendered". Spelling the name plainly and registering it is the honest
# combination; dodging the predicate with a glob would hide the decision.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRIVER="$REPO_ROOT/scripts/adopt-project.sh"
LIB_DIR="$REPO_ROOT/scripts/lib/adopt"
L_ARCHIVE="$LIB_DIR/adopt-archive.sh"
BYPASS_LIB="$REPO_ROOT/scripts/lib/bypass-audit.sh"
BL029="$REPO_ROOT/tests/test-bl029-integration.sh"
LIFECYCLE_DOC="$REPO_ROOT/docs/audit-log-lifecycle.md"

PASSED=0
FAILED=0
SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip_() { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for tests/test-brownfield-wp6-collision-archive.sh" >&2
  exit 2
fi

HAVE_GITLEAKS=0
command -v gitleaks >/dev/null 2>&1 && HAVE_GITLEAKS=1
GITLEAKS_ABSENT_IS_FATAL=0
[ -n "${CI:-}" ] && GITLEAKS_ABSENT_IS_FATAL=1

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/fixXXXXXX"; }

# ── HOST GIT CONFIG IS NEUTRALIZED, AND IT HAD TO BE (R-WP6-3) ─────────────
#
# MEASURED ON THIS HOST, NOT ANTICIPATED. `~/.config/git/ignore` contains
# `**/.claude/settings.local.json`. That is the ecosystem-standard line, it is
# on a great many developer machines, and it is a GLOBAL EXCLUDES FILE — so
# `git check-ignore` inside a fixture consulted it and reported the fixture's
# ARCHIVE COPY as ignored. On this laptop the R-WP6-1 exposure was therefore
# invisible; on a CI runner, which has no such file, it was live. A fixture
# whose verdict is decided by whose machine it runs on is not a fixture.
#
# `GIT_CONFIG_GLOBAL` DOES NOT COVER THIS and that is the trap worth spelling
# out: the excludes file is found at `$XDG_CONFIG_HOME/git/ignore` (falling
# back to `$HOME/.config/git/ignore`), which is a PATH DEFAULT, not a config
# key. Pointing GIT_CONFIG_GLOBAL at /dev/null neutralizes `core.excludesFile`
# and nothing else. XDG_CONFIG_HOME is the knob that matters, and H0 below
# proves it in both directions rather than asserting it.
#
# Same class as the house rules' `GITHUB_BASE_REF` provision: the fixture must
# own every input git reads.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export XDG_CONFIG_HOME="$TOPTMP/xdg"
mkdir -p "$XDG_CONFIG_HOME"

# THE FILE SCOPES ARE NOT ALL THE SCOPES (R-WP6-13). Three more channels reach
# git without touching any file the four exports above neutralise, and the
# first of them OUTRANKS every one of them:
#
#   GIT_CONFIG_COUNT / GIT_CONFIG_KEY_n / GIT_CONFIG_VALUE_n
#       COMMAND scope, which is the highest precedence git has. Measured: with
#       every file scope pointed at /dev/null, one of these pairs setting
#       `core.excludesFile` still decides a fixture path. Unsetting COUNT is
#       sufficient and is the whole gate — git reads it first and ignores the
#       KEY_n/VALUE_n pairs entirely without it.
#   GIT_TEMPLATE_DIR
#       Seeds `info/exclude` into EVERY repository `git init` creates, so it
#       reaches fixtures that are created after this line runs. Measured: a
#       template `info/exclude` decides a fresh fixture's paths.
#   GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE / GIT_OBJECT_DIRECTORY / …
#       Live whenever anything runs a suite from inside a git hook, which
#       points fixture operations at the WRONG REPOSITORY.
#
# None is set on this host, so this is a completeness fix against the principle
# the block above states — the fixture must own every input git reads — rather
# than a live hazard. H0b measures the first two in both directions anyway,
# because "not set today" is a property of today.
unset GIT_CONFIG_COUNT GIT_TEMPLATE_DIR
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
unset GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_COMMON_DIR

# ── Portable primitives (house pattern, WP2/WP4 parity) ─────────────────────
_mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || printf '?\n'; }
_num()     { case "$1" in ''|null|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$1" ;; esac }
_parses()  { bash -n "$1" >/dev/null 2>&1 && printf '1\n' || printf '0\n'; }
_sites()   { local n; n=$(grep -c "$2\$" "$1" 2>/dev/null); _num "$n"; }
_sha()     { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}' || sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

_sed_inplace() {
  local file="$1" expr="$2" tmp mode
  mode="$(_mode_of "$file")"
  tmp="$(mktemp)"
  sed "$expr" "$file" > "$tmp" && mv "$tmp" "$file"
  [ "$mode" != "?" ] && chmod "$mode" "$file" 2>/dev/null
  return 0
}

_changed_lines() {
  local n
  n=$(diff "$1" "$2" 2>/dev/null | grep -c '^[<>]')
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s\n' "$n"
}

# _count_in FILE STRING — fixed-string occurrences, 0 when the file is absent.
_count_in() {
  local n
  [ -f "$1" ] || { printf '0\n'; return 0; }
  n=$(grep -c -F -- "$2" "$1" 2>/dev/null)
  _num "$n"
}

# ── The plant, assembled from halves ────────────────────────────────────────
# So that this source file does not itself carry a 20-character AKIA-shaped
# literal that a secret scanner pointed at THIS repository would report. The
# halves are inert; the join is what matches.
HOOK_PLANT="AKIA3XN7QW5Z""TBMR2VKD"

if [ ! -f "$DRIVER" ]; then
  echo "  [FAIL] setup — $DRIVER not found"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

# ── The fixture ─────────────────────────────────────────────────────────────
mk_adoptee() {
  local p="$1"
  mkdir -p "$p/src" "$p/docs" || return 1
  ( cd "$p" \
      && git init -q . \
      && git config user.email "wp6@test.invalid" \
      && git config user.name  "WP6 Test" ) >/dev/null 2>&1 || return 1
  printf '{"name":"acme-api","scripts":{"test":"npm test"}}\n' > "$p/package.json"
  printf '# acme-api\n' > "$p/README.md"
  printf '# What this is for\n\nInvoice reconciliation for small firms.\n' > "$p/docs/product.md"
  printf '# Architecture\n\nA node service and a postgres database.\n' > "$p/docs/architecture.md"
  ( cd "$p" && git add -A && git commit -q -m "chore: their own history" ) >/dev/null 2>&1 || return 1
  return 0
}

# _add_surfaces DIR [PLANT] — the archive-and-replace surfaces the adoptee
# already occupies (§7.1's first row), and DELIBERATELY NOT ALL OF THEM.
#
# `.mcp.json` and `.claude/settings.local.json` are LEFT ABSENT on purpose:
# §7.2's "only files that exist are archived" is a claim that needs a negative
# to be worth asserting, and a fixture that carries every surface can only
# prove the positive half.
#
# The pre-commit hook names two tools from the description generator's closed
# vocabulary (`npx`, `lint-staged`) so the §7.2 description requirement has a
# POSITIVE control, and — when a plant is passed — carries a BASE32-valid key
# in an `export` line, which is the §7.3 hazard in its most ordinary form.
#
# THE HOOK MUST EXIT 0, AND FINDING OUT WHY COST A FAILING MUTATION. WP4
# installs the framework's hooks AFTER the adoption commit on purpose: the
# adoptee's OWN hooks judge that commit. A fixture hook that really ran
# `npx lint-staged` therefore exited 127 on a host without npx, the adoption
# commit was REJECTED, and two probes went quiet about it — S1's `git ls-files`
# reads the INDEX, which is populated whether or not the commit lands, and S2's
# "the plant is in no committed file" was trivially true because there was no
# adoption commit at all. S4's mutation is what surfaced it: the mutant staged
# the secret-bearing entry exactly as predicted and the plant still could not
# be found in HEAD. The hook now names its tools in a comment and exits 0 —
# §7.2's description is a SHALLOW STATIC READ of the whole file, so the
# positive control is unaffected — every tracked-ness probe reads
# `git ls-tree HEAD`, and every case that depends on a commit asserts the
# commit landed.
_add_surfaces() {
  local d="$1" plant="${2:-}"
  mkdir -p "$d/.claude/skills/invoice-helper" "$d/.git/hooks" || return 1
  printf '{"permissions":{"allow":["Bash(npm test:*)"]},"hooks":{}}\n' > "$d/.claude/settings.json"
  printf '# invoice-helper\n\nTheir own skill.\n' > "$d/.claude/skills/invoice-helper/SKILL.md"
  {
    printf '#!/usr/bin/env bash\n'
    [ -n "$plant" ] && printf 'export AWS_ACCESS_KEY_ID=%s\n' "$plant"
    printf '# on a developer machine this hook runs: npx lint-staged\n'
    printf 'exit 0\n'
  } > "$d/.git/hooks/pre-commit"
  chmod 755 "$d/.git/hooks/pre-commit"
  printf '#!/usr/bin/env bash\n# their own commit-msg hook\nexit 0\n' > "$d/.git/hooks/commit-msg"
  chmod 755 "$d/.git/hooks/commit-msg"
  # A `.sample` hook must NEVER be archived: git ships them in every repo and
  # archiving them would bury the operator's real hooks in noise.
  printf '#!/bin/sh\nexit 0\n' > "$d/.git/hooks/pre-push.sample"
  return 0
}

mk_mirror() {
  local m="$1"
  mkdir -p "$m" || return 1
  cp -Rp "$REPO_ROOT/scripts" "$m/" || return 1
  cp -p "$REPO_ROOT/init.sh" "$m/" || return 1
  return 0
}

# ── The scan report, produced ONCE by the real scanner ──────────────────────
TEMPLATE="$(newtmp)/template"
REPORT=""
REPORT_OK=0
if mk_adoptee "$TEMPLATE"; then
  if bash "$REPO_ROOT/scripts/scout.sh" --root "$TEMPLATE" --out "$TOPTMP/scan" >/dev/null 2>&1; then
    REPORT="$TOPTMP/scan/scout-report.json"
    [ -s "$REPORT" ] && REPORT_OK=1
  fi
fi
if [ "$REPORT_OK" -ne 1 ]; then
  echo "  [FAIL] setup — scripts/scout.sh produced no report; the driver consumes it"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi
jq '.phaseMap.suggestedPhase = 2' "$REPORT" > "$TOPTMP/report.json" 2>/dev/null

# ── Answers ─────────────────────────────────────────────────────────────────
_ans() {
  cat <<'ANS'
2
3
2
1
1
we reconcile vendor invoices by hand
six weeks and no budget
invoices only; no reporting in the first version
public
typescript and postgres are settled
subscription billing
just me approves things
anyone with a login
aws
losing the database
1
1
ANS
}

RUN_RC=0; RUN_OUT=""; RUN_ERR=""
run_adopt() {
  local dir="$1" answers="$2" fw="${3:-$REPO_ROOT}" glbin="${4:-}"
  RUN_RC=0
  RUN_OUT="$(dirname "$answers")/run-out"
  RUN_ERR="$(dirname "$answers")/run-err"
  ( cd "$dir" && SOIF_ADOPT_GITLEAKS_BIN="$glbin" bash "$fw/scripts/adopt-project.sh" \
      --scan-report "$TOPTMP/report.json" ) < "$answers" > "$RUN_OUT" 2> "$RUN_ERR" || RUN_RC=$?
  return 0
}

READD_RC=0; READD_OUT=""; READD_ERR=""
run_readd() {
  local dir="$1" path="$2" answers="$3" fw="${4:-$REPO_ROOT}"
  READD_RC=0
  READD_OUT="$(dirname "$answers")/readd-out"
  READD_ERR="$(dirname "$answers")/readd-err"
  ( cd "$dir" && bash "$fw/scripts/adopt-project.sh" --re-add "$path" ) \
    < "$answers" > "$READD_OUT" 2> "$READD_ERR" || READD_RC=$?
  return 0
}

# arch_dir_of DIR — the one archive directory, relative to the adoptee root.
arch_dir_of() {
  ( cd "$1" 2>/dev/null || return 1
    find .claude/adoption-archive -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort | head -1 )
}

# _in_head DIR PATH — 1 when PATH is in the COMMIT, 0 otherwise.
#
# `git ls-tree HEAD` and NOT `git ls-files`, and the difference is the whole
# reason this helper exists rather than being written inline. `git ls-files`
# reads the INDEX: a path that was `git add`ed reports as tracked even if the
# commit that was supposed to carry it was refused by a hook. Every assertion
# in this suite about what adoption COMMITTED must read the commit.
_in_head() {
  local n
  n=$( cd "$1" 2>/dev/null && git ls-tree -r --name-only HEAD 2>/dev/null | grep -cxF -- "$2" )
  _num "$n"
}

# _adoption_commit_landed DIR — 1 when HEAD is the adoption commit.
# The control every committed-tree assertion needs: "the plant is in no
# committed file" is satisfied just as well by there being no commit.
_adoption_commit_landed() {
  local s
  s=$( cd "$1" 2>/dev/null && git log -1 --format=%s 2>/dev/null )
  case "$s" in
    "chore: adopt "*) printf '1\n' ;;
    *)               printf '0\n' ;;
  esac
}

# _add_local_settings DIR PAYLOAD — the modal adoptee shape: a gitignored
# `.claude/settings.local.json` holding something private that IS NOT
# SECRET-SHAPED. An internal hostname and a username match no scanner pattern,
# which is the point — the only thing standing between them and the commit is
# the operator's own ignore rule.
_add_local_settings() {
  local d="$1" payload="$2"
  mkdir -p "$d/.claude" || return 1
  printf '{"env":{"HTTPS_PROXY":"%s"},"user":"%s"}\n' "$payload" "$payload" > "$d/.claude/settings.local.json"
  return 0
}

# ═══════════════════════════════════════════════════════════════════════════
echo "=== H0 — the fixtures are isolated from host git config (R-WP6-3) ==="

# TWO DIRECTIONS, because a neutralization nobody tested is a comment. The
# probe writes the exact line this host really carries into a THROWAWAY
# XDG_CONFIG_HOME, proves git honours it (so the knob is live and the hazard is
# real), then proves the suite's own isolated XDG_CONFIG_HOME does not.
H0="$(newtmp)"
h0_ok=0
if mk_adoptee "$H0/p"; then
  mkdir -p "$H0/xdg-host/git"
  printf '**/.claude/settings.local.json\n' > "$H0/xdg-host/git/ignore"
  h0_probe=".claude/adoption-archive/T-1/.claude/settings.local.json"
  h0_with=1
  ( cd "$H0/p" && XDG_CONFIG_HOME="$H0/xdg-host" git check-ignore -q -- "$h0_probe" ) 2>/dev/null || h0_with=0
  h0_without=1
  ( cd "$H0/p" && git check-ignore -q -- "$h0_probe" ) 2>/dev/null || h0_without=0
  h0_ok=1
fi
if [ "$h0_ok" -eq 1 ] && [ "$h0_with" -eq 1 ] && [ "$h0_without" -eq 0 ]; then
  pass "H0: a global excludes file DOES decide an archive path (ignored=$h0_with with one in scope) and the suite's isolated XDG_CONFIG_HOME removes it (ignored=$h0_without) — the fixtures below are the suite's, not the host's"
else
  fail_ "H0" "setup=$h0_ok ignored-with-host-excludes=$h0_with (want 1 — the knob must be live, or this proves nothing) ignored-under-isolation=$h0_without (want 0)"
fi

# H0b — the other two channels, same two-direction shape as H0.
H0B="$(newtmp)"
h0b_ok=0
if mk_adoptee "$H0B/p"; then
  printf 'settings.local.json\n' > "$H0B/inject"
  h0b_probe=".claude/adoption-archive/T-1/.claude/settings.local.json"
  h0b_cfg_with=1
  ( cd "$H0B/p" && GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.excludesFile GIT_CONFIG_VALUE_0="$H0B/inject" \
      git check-ignore -q -- "$h0b_probe" ) 2>/dev/null || h0b_cfg_with=0
  h0b_cfg_without=1
  ( cd "$H0B/p" && git check-ignore -q -- "$h0b_probe" ) 2>/dev/null || h0b_cfg_without=0
  # GIT_TEMPLATE_DIR reaches repositories created AFTER it is set, so the probe
  # creates one each way rather than reusing the fixture above.
  mkdir -p "$H0B/tpl/info"; printf 'settings.local.json\n' > "$H0B/tpl/info/exclude"
  mkdir -p "$H0B/t1" "$H0B/t2"
  h0b_tpl_with=1
  ( cd "$H0B/t1" && GIT_TEMPLATE_DIR="$H0B/tpl" git init -q . && git check-ignore -q -- "$h0b_probe" ) 2>/dev/null || h0b_tpl_with=0
  h0b_tpl_without=1
  ( cd "$H0B/t2" && git init -q . && git check-ignore -q -- "$h0b_probe" ) 2>/dev/null || h0b_tpl_without=0
  h0b_ok=1
fi
if [ "$h0b_ok" -eq 1 ] && [ "$h0b_cfg_with" -eq 1 ] && [ "$h0b_cfg_without" -eq 0 ] \
   && [ "$h0b_tpl_with" -eq 1 ] && [ "$h0b_tpl_without" -eq 0 ]; then
  pass "H0b (R-WP6-13): GIT_CONFIG_COUNT (command scope, outranking every file scope) and GIT_TEMPLATE_DIR both DO decide a fixture path when set, and neither does under the suite's unset preamble"
else
  fail_ "H0b" "setup=$h0b_ok GIT_CONFIG_COUNT decides when set=$h0b_cfg_with (want 1 — else the channel is not real) and when unset=$h0b_cfg_without (want 0); GIT_TEMPLATE_DIR when set=$h0b_tpl_with (want 1) and when unset=$h0b_tpl_without (want 0)"
fi

echo ""
echo "=== A — the archive layout and its MANIFEST (§7.2) ==="

A_D="$(newtmp)"
A_OK=0
if mk_adoptee "$A_D/p" && _add_surfaces "$A_D/p"; then
  _ans > "$A_D/answers"
  run_adopt "$A_D/p" "$A_D/answers"
  A_OK=1
fi

if [ "$A_OK" -ne 1 ]; then
  fail_ "A (setup)" "fixture setup failed"
  A_ARCH=""
else
  A_ARCH="$(arch_dir_of "$A_D/p")"
fi
A_MJ="$A_D/p/$A_ARCH/MANIFEST.json"
A_MD="$A_D/p/$A_ARCH/MANIFEST.md"

# A1 — the directory exists, under the designed root, with the designed name
# shape. `<UTC-timestamp>-<pid>` inherited from _upgrade_snapshot_pre_mutation.
if [ -n "$A_ARCH" ] \
   && printf '%s' "$A_ARCH" | grep -Eq '^\.claude/adoption-archive/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}Z-[0-9]+(-[0-9]+)?$'; then
  pass "A1: the archive is at .claude/adoption-archive/<UTC-timestamp>-<pid> — $A_ARCH"
else
  fail_ "A1" "archive dir='$A_ARCH' (want .claude/adoption-archive/<ts>-<pid>); run_rc=$RUN_RC"
fi

# A2 — relative paths MIRRORED, and git hooks under `git-hooks/` (§7.2's tree).
#
# EVERY PROBE IS GUARDED ON A NON-EMPTY `$A_ARCH`. With it empty the paths
# below collapse onto the ADOPTEE'S OWN `.claude/settings.json`, and the probe
# reports the archive mirrored a file it never touched — measured on this
# suite's watched-RED run, where it also silently supplied A3's positive
# control.
a2_set=0; a2_skill=0; a2_hook=0; a2_cm=0
if [ -n "$A_ARCH" ]; then
  [ -f "$A_D/p/$A_ARCH/.claude/settings.json" ] && a2_set=1
  [ -f "$A_D/p/$A_ARCH/.claude/skills/invoice-helper/SKILL.md" ] && a2_skill=1
  [ -f "$A_D/p/$A_ARCH/git-hooks/pre-commit" ] && a2_hook=1
  [ -f "$A_D/p/$A_ARCH/git-hooks/commit-msg" ] && a2_cm=1
fi
if [ "$a2_set" -eq 1 ] && [ "$a2_skill" -eq 1 ] && [ "$a2_hook" -eq 1 ] && [ "$a2_cm" -eq 1 ]; then
  pass "A2: original paths are mirrored relative to the project root, and .git/hooks/* lands under git-hooks/"
else
  fail_ "A2" "settings=$a2_set skill=$a2_skill pre-commit=$a2_hook commit-msg=$a2_cm (all want 1)"
fi

# A3 — ONLY FILES THAT EXIST. The fixture has no .mcp.json and no
# settings.local.json; a spurious empty file or a phantom entry is the defect.
# The positive half (A2) and the negative half are asserted together, because
# an archive that contains nothing at all would satisfy the negative alone.
a3_files=0; a3_entries=0
# `$A_ARCH` EMPTY MUST NOT DEGRADE INTO A SEARCH OF THE ADOPTEE ROOT. Without
# the guard, an absent archive makes `find "$root/"` walk the whole fixture and
# this case reports a "finding" from the operator's own tree — an assertion
# that answers a question nobody asked.
[ -n "$A_ARCH" ] && \
a3_files=$(find "$A_D/p/$A_ARCH" \( -name '.mcp.json' -o -name 'settings.local.json' -o -name 'pre-push.sample' \) 2>/dev/null | grep -c .)
a3_files=$(_num "$a3_files")
a3_entries=$(jq -r '[.entries[] | select(.originalPath == ".mcp.json" or .originalPath == ".claude/settings.local.json" or (.originalPath | test("\\.sample$")))] | length' "$A_MJ" 2>/dev/null)
a3_entries=$(_num "$a3_entries")
if [ "$a3_files" -eq 0 ] && [ "$a3_entries" -eq 0 ] && [ "$a2_set" -eq 1 ]; then
  pass "A3: only files that EXIST are archived — no .mcp.json, no settings.local.json, no .sample hook, and no phantom MANIFEST entry for any of them"
else
  fail_ "A3" "absent-surface files in archive=$a3_files (want 0) phantom entries=$a3_entries (want 0) control settings.json present=$a2_set (want 1)"
fi

# A4 — the MANIFEST lists EVERY entry, both directions.
a4_files=$( cd "$A_D/p/$A_ARCH" 2>/dev/null && find . -type f 2>/dev/null | sed 's|^\./||' | grep -v '^MANIFEST\.' | LC_ALL=C sort )
a4_listed=$(jq -r '.entries[].archivedPath' "$A_MJ" 2>/dev/null | LC_ALL=C sort)
a4_n=$(printf '%s\n' "$a4_files" | grep -c .); a4_n=$(_num "$a4_n")
a4_match=0
[ "$a4_files" = "$a4_listed" ] && a4_match=1
if [ "$a4_match" -eq 1 ] && [ "$a4_n" -ge 4 ]; then
  pass "A4: the MANIFEST lists EVERY archived file and no others — $a4_n entries, bijective with the tree"
else
  fail_ "A4" "archived files=[$(printf '%s' "$a4_files" | tr '\n' ' ')] listed=[$(printf '%s' "$a4_listed" | tr '\n' ' ')] n=$a4_n (want >=4)"
fi

# A5 — every entry carries a RESTORE line, and one of them is EXECUTED.
# A restore string nobody runs is documentation; running it is the assertion.
a5_missing=$(jq -r '[.entries[] | select((.restore // "") == "")] | length' "$A_MJ" 2>/dev/null); a5_missing=$(_num "$a5_missing")
a5_cmd=$(jq -r '.entries[] | select(.originalPath == ".git/hooks/pre-commit") | .restore' "$A_MJ" 2>/dev/null)
a5_before=""; a5_after=""; a5_mode=""; a5_ran=0
if [ -n "$a5_cmd" ] && [ -f "$A_D/p/.git/hooks/pre-commit" ]; then
  a5_before="$(_sha "$A_D/p/.git/hooks/pre-commit")"
  rm -f "$A_D/p/.git/hooks/pre-commit"
  ( cd "$A_D/p" && eval "$a5_cmd" ) >/dev/null 2>&1 && a5_ran=1
  a5_after="$(_sha "$A_D/p/.git/hooks/pre-commit")"
  a5_mode="$(_mode_of "$A_D/p/.git/hooks/pre-commit")"
fi
if [ "$a5_missing" -eq 0 ] && [ "$a5_ran" -eq 1 ] && [ -n "$a5_before" ] && [ "$a5_before" = "$a5_after" ] && [ "$a5_mode" = "755" ]; then
  pass "A5: every entry carries a restore line, and the git-hook one RUNS — the file comes back byte-identical at mode 755"
else
  fail_ "A5" "entries with no restore=$a5_missing (want 0) restore_ran=$a5_ran before=$a5_before after=$a5_after mode=$a5_mode (want 755) cmd=[$a5_cmd]"
fi

# A6 — a `git-hook` entry carries a DESCRIPTION, it is derived from a closed
# tool vocabulary, and it quotes NO byte of the hook (§7.2 + §7.3's hazard).
a6_class=$(jq -r '.entries[] | select(.originalPath == ".git/hooks/pre-commit") | .class' "$A_MJ" 2>/dev/null)
a6_desc=$(jq -r '.entries[] | select(.originalPath == ".git/hooks/pre-commit") | .description // ""' "$A_MJ" 2>/dev/null)
a6_nondesc=$(jq -r '[.entries[] | select(.class == "git-hook") | select((.description // "") == "")] | length' "$A_MJ" 2>/dev/null); a6_nondesc=$(_num "$a6_nondesc")
a6_names=0
printf '%s' "$a6_desc" | grep -q 'lint-staged' && a6_names=1
a6_advisory=0
jq -e '(.advisory // "") | test("advisory"; "i")' "$A_MJ" >/dev/null 2>&1 && a6_advisory=1
if [ "$a6_class" = "git-hook" ] && [ "$a6_nondesc" -eq 0 ] && [ "$a6_names" -eq 1 ] && [ "$a6_advisory" -eq 1 ]; then
  pass "A6: every git-hook entry carries a description; it names the tool the hook invokes (lint-staged) and the MANIFEST says it is ADVISORY"
else
  fail_ "A6" "class=$a6_class git-hook entries with no description=$a6_nondesc (want 0) names_lint-staged=$a6_names advisory_header=$a6_advisory desc=[$a6_desc]"
fi

# A7 — the MANIFEST is machine-readable and self-locating.
a7_ver=$(jq -r '.schemaVersion // "MISSING"' "$A_MJ" 2>/dev/null)
a7_dir=$(jq -r '.archiveDir // "MISSING"' "$A_MJ" 2>/dev/null)
a7_at=$(jq -r '.adoptedAt // ""' "$A_MJ" 2>/dev/null)
a7_md=0; [ -s "$A_MD" ] && a7_md=1
if [ "$a7_ver" = "1" ] && [ "$a7_dir" = "$A_ARCH" ] && [ -n "$a7_at" ] && [ "$a7_md" -eq 1 ]; then
  pass "A7: MANIFEST.json parses with schemaVersion 1 and archiveDir equal to its own location, and MANIFEST.md exists beside it"
else
  fail_ "A7" "schemaVersion=$a7_ver archiveDir=$a7_dir (want $A_ARCH) adoptedAt=[$a7_at] MANIFEST.md=$a7_md"
fi

# A8 — the collision loop. Two archives inside the SAME wall-clock second must
# not be the same directory. Asserted by CALLING the allocator twice, not by
# reading the loop: `-1`/`-2` in the source proves nothing about what runs.
A8="$(newtmp)"
mkdir -p "$A8/p"
a8_one=""; a8_two=""; a8_probe=0
if [ -f "$L_ARCHIVE" ]; then
  a8_pair="$( . "$L_ARCHIVE" >/dev/null 2>&1
              one="$(adopt_archive_dir_new "$A8/p")"; mkdir -p "$A8/p/$one"
              two="$(adopt_archive_dir_new "$A8/p")"
              printf '%s\n%s\n' "$one" "$two" )"
  a8_one="$(printf '%s\n' "$a8_pair" | sed -n '1p')"
  a8_two="$(printf '%s\n' "$a8_pair" | sed -n '2p')"
  [ -n "$a8_one" ] && a8_probe=1
fi
if [ "$a8_probe" -eq 1 ] && [ -n "$a8_two" ] && [ "$a8_one" != "$a8_two" ]; then
  pass "A8: a second archive allocated in the same second gets a distinct directory ($a8_one vs $a8_two)"
else
  fail_ "A8" "probe_ran=$a8_probe first=[$a8_one] second=[$a8_two] (want two different non-empty names)"
fi

echo ""
echo "=== D — the disclosure (§7.3: the sentence, the LIST, the restore) ==="

# The design's own words, spelled here independently of the source so the pin
# is a string equality against the design and not a tautology.
DISCLOSURE_SENTENCE="moved to ensure the framework operates properly"

d1=$(_count_in "$RUN_OUT" "$DISCLOSURE_SENTENCE")
if [ "$d1" -ge 1 ]; then
  pass "D1: the disclosure prints the design's sentence — 'moved to ensure the framework operates properly'"
else
  fail_ "D1" "occurrences in the transcript=$d1 (want >=1)"
fi

# D2 — THE LIST, NOT A COUNT. Every archived original path must be named.
d2_missing=""
if [ -f "$A_MJ" ]; then
  while IFS= read -r op; do
    [ -n "$op" ] || continue
    if [ "$(_count_in "$RUN_OUT" "$op")" -eq 0 ]; then d2_missing="$d2_missing $op"; fi
  done <<D2SET
$(jq -r '.entries[].originalPath' "$A_MJ" 2>/dev/null)
D2SET
fi
d2_n=$(jq -r '.entries | length' "$A_MJ" 2>/dev/null); d2_n=$(_num "$d2_n")
if [ -z "$d2_missing" ] && [ "$d2_n" -ge 4 ]; then
  pass "D2: the disclosure names EVERY archived path ($d2_n of them), not a summary count"
else
  fail_ "D2" "paths absent from the transcript:$d2_missing entries=$d2_n (want >=4)"
fi

# D3 — the restore INSTRUCTIONS, and they must name the real archive directory.
# `$A_ARCH` empty would make the grep an EMPTY PATTERN, which matches every
# line of the transcript and turns this into a line count. Guarded.
d3_dir=0
[ -n "$A_ARCH" ] && d3_dir=$(_count_in "$RUN_OUT" "$A_ARCH")
d3_cp=$(_count_in "$RUN_OUT" "cp .claude/adoption-archive/")
if [ -n "$A_ARCH" ] && [ "$d3_dir" -ge 1 ] && [ "$d3_cp" -ge 1 ]; then
  pass "D3: the disclosure prints restore instructions naming the real archive directory"
else
  fail_ "D3" "archive dir named=$d3_dir (want >=1) restore command shown=$d3_cp (want >=1)"
fi

echo ""
echo "=== S — §7.3's exposure: the archive is scanned BEFORE staging ==="

if [ "$HAVE_GITLEAKS" -ne 1 ]; then
  echo ""
  echo "  ***********************************************************************"
  echo "  *  gitleaks IS NOT INSTALLED ON THIS HOST.                            *"
  echo "  *  The §7.3 archive-secrets proof and its mutation DID NOT RUN.       *"
  echo "  *  Nobody looked. This is not a clean result.                         *"
  echo "  *  Install it:  brew install gitleaks                                 *"
  echo "  ***********************************************************************"
  echo ""
fi

if [ "$HAVE_GITLEAKS" -eq 1 ]; then
  S_D="$(newtmp)"
  S_OK=0
  if mk_adoptee "$S_D/p" && _add_surfaces "$S_D/p" "$HOOK_PLANT"; then
    _ans > "$S_D/answers"
    run_adopt "$S_D/p" "$S_D/answers"
    S_OK=1
  fi
  S_ARCH="$(arch_dir_of "$S_D/p")"
  S_MJ="$S_D/p/$S_ARCH/MANIFEST.json"
  S_MD="$S_D/p/$S_ARCH/MANIFEST.md"

  # ── S0 — THE PRECONDITION. Everything below is vacuous without it. ────────
  s0_status=$(jq -r '.secretsScan.status // "MISSING"' "$S_MJ" 2>/dev/null)
  s0_count=$(jq -r '.secretsScan.findingCount // "null"' "$S_MJ" 2>/dev/null); s0_count=$(_num "$s0_count")
  s0_copy=$(_count_in "$S_D/p/$S_ARCH/git-hooks/pre-commit" "$HOOK_PLANT")
  s0_pre=$(_count_in "$S_D/p/.git/hooks/pre-commit" "$HOOK_PLANT")
  if [ "$S_OK" -eq 1 ] && [ "$s0_status" = "scanned" ] && [ "$s0_count" -ge 1 ] \
     && [ "$s0_copy" -eq 1 ] && [ "$s0_pre" -eq 1 ]; then
    pass "S0 PRECONDITION: the BASE32-valid plant is live in the hook, the archive copied it (probe sees it exactly $s0_copy time), and the scan reports status=scanned with findingCount=$s0_count (non-zero)"
  else
    fail_ "S0 PRECONDITION" "setup=$S_OK status='$s0_status' (want scanned) findingCount=$s0_count (want >=1) plant-in-archive-copy=$s0_copy (want 1) plant-in-hook=$s0_pre (want 1) — a dud plant makes every assertion below vacuous"
  fi

  # ── S1 — the matching entry REFUSES TO STAGE ─────────────────────────────
  s1_staged=$(jq -r '.entries[] | select(.originalPath == ".git/hooks/pre-commit") | .stagedForCommit' "$S_MJ" 2>/dev/null)
  s1_reason=$(jq -r '.entries[] | select(.originalPath == ".git/hooks/pre-commit") | .withheldReason // ""' "$S_MJ" 2>/dev/null)
  s1_tracked=$(_in_head "$S_D/p" "$S_ARCH/git-hooks/pre-commit")
  # The clean sibling in the SAME archive must still be committed, or "nothing
  # was staged" would satisfy this assertion just as well as a targeted
  # refusal — and the adoption commit itself must have LANDED, or "not in the
  # commit" would be a statement about a commit that does not exist.
  s1_sib=$(_in_head "$S_D/p" "$S_ARCH/.claude/settings.json")
  s1_landed=$(_adoption_commit_landed "$S_D/p")
  if [ "$s1_staged" = "false" ] && [ "$s1_reason" = "secret-match" ] \
     && [ "$s1_landed" -eq 1 ] && [ "$s1_tracked" -eq 0 ] && [ "$s1_sib" -eq 1 ]; then
    pass "S1: the matching entry REFUSES TO STAGE (stagedForCommit=false, withheldReason=secret-match, absent from HEAD) while its clean sibling in the same archive IS in the adoption commit"
  else
    fail_ "S1" "stagedForCommit='$s1_staged' (want false) withheldReason='$s1_reason' (want secret-match) adoption commit landed=$s1_landed (want 1) in HEAD=$s1_tracked (want 0) clean-sibling in HEAD=$s1_sib (want 1)"
  fi

  # ── S2 — the plant reaches NO artifact byte ──────────────────────────────
  # THIS CASE CARRIES S0'S PRECONDITION IN ITS OWN CONDITION, and that is not
  # belt-and-braces. Measured during the watched-RED run of this suite, with
  # the module absent: every artifact below was missing, the plant was
  # therefore in zero of them, and S2 PASSED — a green assertion about files
  # that did not exist. An absence proves nothing until the thing that could
  # have leaked has been shown to exist and to contain the plant.
  #
  # The committed-tree probe gets its own positive control too: `git grep` over
  # HEAD must find something that IS committed, or "found nothing" would be
  # indistinguishable from "searched nothing".
  s2_ctrl=$( cd "$S_D/p" && git grep -F -l -- "acme-api" HEAD 2>/dev/null | grep -c . ); s2_ctrl=$(_num "$s2_ctrl")
  s2_tree=$( cd "$S_D/p" && git grep -F -l -- "$HOOK_PLANT" HEAD 2>/dev/null | grep -c . ); s2_tree=$(_num "$s2_tree")
  s2_mj=$(_count_in "$S_MJ" "$HOOK_PLANT")
  s2_md=$(_count_in "$S_MD" "$HOOK_PLANT")
  s2_out=$(_count_in "$RUN_OUT" "$HOOK_PLANT")
  s2_err=$(_count_in "$RUN_ERR" "$HOOK_PLANT")
  s2_ledger=$(_count_in "$S_D/p/.claude/bypass-audit.json" "$HOOK_PLANT")
  if [ "$s0_copy" -eq 1 ] && [ "$s0_count" -ge 1 ] && [ -s "$S_MJ" ] && [ -s "$S_MD" ] \
     && [ "$(_adoption_commit_landed "$S_D/p")" -eq 1 ] \
     && [ "$s2_ctrl" -ge 1 ] && [ "$s2_tree" -eq 0 ] && [ "$s2_mj" -eq 0 ] && [ "$s2_md" -eq 0 ] \
     && [ "$s2_out" -eq 0 ] && [ "$s2_err" -eq 0 ] && [ "$s2_ledger" -eq 0 ]; then
    pass "S2: the plant occurs in ZERO bytes of the committed tree, MANIFEST.json, MANIFEST.md, the transcript and the audit ledger — while provably present once in the archive copy, and with the tree probe proven able to see a committed token ($s2_ctrl file)"
  else
    fail_ "S2" "precondition: plant-in-archive-copy=$s0_copy (want 1) findingCount=$s0_count (want >=1) MANIFEST.json non-empty=$([ -s "$S_MJ" ] && echo 1 || echo 0) MANIFEST.md non-empty=$([ -s "$S_MD" ] && echo 1 || echo 0) adoption commit landed=$(_adoption_commit_landed "$S_D/p") (want 1); probe control=$s2_ctrl (want >=1); committed tree=$s2_tree MANIFEST.json=$s2_mj MANIFEST.md=$s2_md stdout=$s2_out stderr=$s2_err ledger=$s2_ledger (all want 0)"
  fi

  # ── S3 — POSITIVE CONTROL: a CLEAN archive IS staged ─────────────────────
  # Without this, "refuses to stage" is satisfied by a driver that stages
  # nothing, ever.
  s3_staged=$(jq -r '.entries[] | select(.originalPath == ".git/hooks/pre-commit") | .stagedForCommit' "$A_MJ" 2>/dev/null)
  s3_status=$(jq -r '.secretsScan.status // "MISSING"' "$A_MJ" 2>/dev/null)
  s3_count=$(jq -r '.secretsScan.findingCount // "null"' "$A_MJ" 2>/dev/null)
  s3_tracked=$(_in_head "$A_D/p" "$A_ARCH/git-hooks/pre-commit")
  s3_landed=$(_adoption_commit_landed "$A_D/p")
  if [ "$s3_staged" = "true" ] && [ "$s3_status" = "scanned" ] && [ "$s3_count" = "0" ] \
     && [ "$s3_landed" -eq 1 ] && [ "$s3_tracked" -eq 1 ]; then
    pass "S3 POSITIVE CONTROL: with no plant the same entry IS staged and lands in the adoption commit (status=scanned, findingCount=0) — the refusal is targeted, not a blanket"
  else
    fail_ "S3" "stagedForCommit='$s3_staged' (want true) status='$s3_status' findingCount='$s3_count' (want 0) adoption commit landed=$s3_landed (want 1) in HEAD=$s3_tracked (want 1)"
  fi

  # ── S4 — MUTATION: remove the pre-staging scan ───────────────────────────
  S4="$(newtmp)"
  if ! mk_adoptee "$S4/p" || ! _add_surfaces "$S4/p" "$HOOK_PLANT" || ! mk_mirror "$S4/fw"; then
    fail_ "S4 (MUTATION)" "fixture setup failed"
  else
    MUT="$S4/fw/scripts/lib/adopt/adopt-archive.sh"
    s4_sites=$(_sites "$L_ARCHIVE" 'BF-ADOPT-ARCHIVE-SCAN')
    cp "$L_ARCHIVE" "$S4/orig.ref"
    _sed_inplace "$MUT" 's|^.*BF-ADOPT-ARCHIVE-SCAN$|  printf "scanned\\n" > "$work/arcstatus"   # BF-ADOPT-ARCHIVE-SCAN|'
    s4_chg=$(_changed_lines "$S4/orig.ref" "$MUT")
    s4_parses=$(_parses "$MUT")
    _ans > "$S4/answers"
    run_adopt "$S4/p" "$S4/answers" "$S4/fw"
    s4_arch="$(arch_dir_of "$S4/p")"
    s4_tracked=$(_in_head "$S4/p" "$s4_arch/git-hooks/pre-commit")
    s4_landed=$(_adoption_commit_landed "$S4/p")
    s4_tree=$( cd "$S4/p" && git grep -F -l -- "$HOOK_PLANT" HEAD 2>/dev/null | grep -c . ); s4_tree=$(_num "$s4_tree")
    if [ "$s4_sites" -eq 1 ] && [ "$s4_chg" -eq 2 ] && [ "$s4_parses" -eq 1 ] \
       && [ "$s4_landed" -eq 1 ] && [ "$s4_tracked" -eq 1 ] && [ "$s4_tree" -ge 1 ]; then
      pass "S4 (MUTATION): with the pre-staging scan neutered (1 site, 2 lines, mutant parses) the secret-bearing entry IS committed and the plant appears in $s4_tree committed file(s) — RED"
    else
      fail_ "S4" "sites=$s4_sites (want 1) changed_lines=$s4_chg (want 2) parses=$s4_parses (want 1) adoption commit landed=$s4_landed (want 1) entry in HEAD=$s4_tracked (want 1) plant_in_tree=$s4_tree (want >=1)"
    fi
  fi
  # ── S6 (R-WP6-9) — an inherited GITLEAKS_CONFIG must not switch the scan off
  #
  # This is a SUPPRESSION VECTOR, not a documentation nit. Measured on gitleaks
  # 8.30.1: exporting GITLEAKS_CONFIG (or GITLEAKS_CONFIG_TOML) at a config
  # whose rules match nothing takes the plant from 1 finding to 0 — and those
  # variables OUTRANK the scanned path, so the "the archive dir cannot contain
  # a .gitleaks.toml" argument does not cover them. Anything in the operator's
  # environment — a shell profile, a CI job env, a direnv file in the adoptee —
  # would have silently disabled §7.3's refusal while the MANIFEST still said
  # `status: scanned`, which is the worst available combination.
  #
  # TWO DIRECTIONS. The vector is proved live against the real binary first
  # (or the fix could be pinned against a threat that does not exist), then the
  # driver is run with the same variables exported and must be unaffected.
  S6="$(newtmp)"
  if ! mk_adoptee "$S6/p" || ! _add_surfaces "$S6/p" "$HOOK_PLANT"; then
    fail_ "S6 (R-WP6-9)" "fixture setup failed"
  else
    mkdir -p "$S6/probe"
    cp "$S6/p/.git/hooks/pre-commit" "$S6/probe/hook.sh"
    printf 'title = "suppress"\n[[rules]]\nid = "never-matches"\ndescription = "matches nothing"\nregex = %s\n' \
      "'''NEVERMATCHESANYTHING12345'''" > "$S6/allow.toml"
    ( cd "$S6/probe" && gitleaks dir --no-banner --redact --exit-code 0 -f json -r "$S6/base.json" . ) >/dev/null 2>&1
    ( cd "$S6/probe" && GITLEAKS_CONFIG="$S6/allow.toml" gitleaks dir --no-banner --redact --exit-code 0 -f json -r "$S6/supp.json" . ) >/dev/null 2>&1
    s6_base=$(jq 'length' "$S6/base.json" 2>/dev/null); s6_base=$(_num "$s6_base")
    s6_supp=$(jq 'length' "$S6/supp.json" 2>/dev/null); s6_supp=$(_num "$s6_supp")
    _ans > "$S6/answers"
    RUN_RC=0
    RUN_OUT="$S6/run-out"; RUN_ERR="$S6/run-err"
    ( cd "$S6/p" && GITLEAKS_CONFIG="$S6/allow.toml" GITLEAKS_CONFIG_TOML="$(cat "$S6/allow.toml")" \
        bash "$REPO_ROOT/scripts/adopt-project.sh" --scan-report "$TOPTMP/report.json" ) \
      < "$S6/answers" > "$RUN_OUT" 2> "$RUN_ERR" || RUN_RC=$?
    s6_arch="$(arch_dir_of "$S6/p")"
    s6_mj="$S6/p/$s6_arch/MANIFEST.json"
    s6_count=$(jq -r '.secretsScan.findingCount // "null"' "$s6_mj" 2>/dev/null); s6_count=$(_num "$s6_count")
    s6_reason=$(jq -r '.entries[] | select(.originalPath == ".git/hooks/pre-commit") | .withheldReason // ""' "$s6_mj" 2>/dev/null)
    s6_head=$(_in_head "$S6/p" "$s6_arch/git-hooks/pre-commit")
    if [ "$s6_base" -ge 1 ] && [ "$s6_supp" -eq 0 ] \
       && [ "$s6_count" -ge 1 ] && [ "$s6_reason" = "secret-match" ] && [ "$s6_head" -eq 0 ]; then
      pass "S6 (R-WP6-9): the vector is real — GITLEAKS_CONFIG takes the same file from $s6_base finding(s) to $s6_supp against the raw binary — and the driver is IMMUNE to it: findingCount=$s6_count, the entry is still withheld as secret-match and still absent from HEAD"
    else
      fail_ "S6" "raw binary baseline=$s6_base (want >=1) raw binary under GITLEAKS_CONFIG=$s6_supp (want 0 — else the vector is not real and this proves nothing); driver findingCount=$s6_count (want >=1) withheldReason='$s6_reason' (want secret-match) entry in HEAD=$s6_head (want 0)"
    fi
  fi
else
  skip_ "S0-S4 (§7.3 archive-secrets proof and its mutation)" "gitleaks not installed — see the banner above"
  skip_ "S6 (inherited GITLEAKS_CONFIG cannot suppress the scan)" "gitleaks not installed"
fi

# ── S5 — "nobody looked" is never "clean" ──────────────────────────────────
# Runs WITHOUT gitleaks by construction: it points the driver at a binary name
# that does not exist, so it proves the tool-unavailable arm on any host.
S5="$(newtmp)"
if ! mk_adoptee "$S5/p" || ! _add_surfaces "$S5/p"; then
  fail_ "S5" "fixture setup failed"
else
  _ans > "$S5/answers"
  run_adopt "$S5/p" "$S5/answers" "$REPO_ROOT" "definitely-not-a-real-binary-name"
  s5_arch="$(arch_dir_of "$S5/p")"
  s5_mj="$S5/p/$s5_arch/MANIFEST.json"
  s5_status=$(jq -r '.secretsScan.status // "MISSING"' "$s5_mj" 2>/dev/null)
  s5_count=$(jq -r '.secretsScan.findingCount' "$s5_mj" 2>/dev/null)
  s5_staged=$(jq -r '[.entries[] | select(.stagedForCommit == true)] | length' "$s5_mj" 2>/dev/null); s5_staged=$(_num "$s5_staged")
  s5_reason=$(jq -r '[.entries[] | select(.withheldReason == "not-scanned")] | length' "$s5_mj" 2>/dev/null); s5_reason=$(_num "$s5_reason")
  s5_n=$(jq -r '.entries | length' "$s5_mj" 2>/dev/null); s5_n=$(_num "$s5_n")
  s5_loud=$(_count_in "$RUN_OUT" "NOTHING WAS SCANNED")
  if [ "$s5_status" = "tool-unavailable" ] && [ "$s5_count" = "null" ] \
     && [ "$s5_staged" -eq 0 ] && [ "$s5_n" -ge 4 ] && [ "$s5_reason" -eq "$s5_n" ] && [ "$s5_loud" -ge 1 ]; then
    pass "S5: with the scanner unavailable the archive reports status=tool-unavailable and findingCount=null (NOT 0), every one of its $s5_n entries is withheld with reason 'not-scanned', and the run says so out loud"
  else
    fail_ "S5" "status='$s5_status' (want tool-unavailable) findingCount='$s5_count' (want null) staged=$s5_staged (want 0) entries=$s5_n withheld-as-not-scanned=$s5_reason (want $s5_n) loud=$s5_loud (want >=1)"
  fi
fi

echo ""
echo "=== R — re-adds: permitted, WARNED, and RECORDED (§7.3) ==="

# The design's warning, spelled here independently of the source.
READD_WARNING="Personal systems may conflict with the framework"
READD_WARNING2="accuracy, documentation, and capabilities may be compromised"

R1="$(newtmp)"
R1_OK=0
if mk_adoptee "$R1/p" && _add_surfaces "$R1/p"; then
  _ans > "$R1/answers"
  run_adopt "$R1/p" "$R1/answers"
  R1_OK=1
fi
if [ "$R1_OK" -ne 1 ]; then
  fail_ "R1" "fixture setup failed"
  fail_ "R3" "fixture setup failed"
else
  r1_arch="$(arch_dir_of "$R1/p")"
  # Overwrite the live hook so a restore is observable rather than a no-op.
  printf '#!/usr/bin/env bash\n# replaced\nexit 0\n' > "$R1/p/.git/hooks/pre-commit"
  chmod 700 "$R1/p/.git/hooks/pre-commit"
  r1_want="$(_sha "$R1/p/$r1_arch/git-hooks/pre-commit")"
  printf '1\n' > "$R1/confirm"
  run_readd "$R1/p" ".git/hooks/pre-commit" "$R1/confirm"
  r1_got="$(_sha "$R1/p/.git/hooks/pre-commit")"
  r1_mode="$(_mode_of "$R1/p/.git/hooks/pre-commit")"
  r1_w1=$(_count_in "$READD_OUT" "$READD_WARNING")
  r1_w2=$(_count_in "$READD_OUT" "$READD_WARNING2")
  r1_rows=$(jq -r '[.[] | select(.type == "adoption_event") | select(.details.event == "collision_re_add")] | length' "$R1/p/.claude/bypass-audit.json" 2>/dev/null); r1_rows=$(_num "$r1_rows")
  r1_path=$(jq -r '[.[] | select(.type == "adoption_event") | select(.details.event == "collision_re_add")] | .[0].details.path // ""' "$R1/p/.claude/bypass-audit.json" 2>/dev/null)
  if [ "$READD_RC" -eq 0 ] && [ -n "$r1_want" ] && [ "$r1_want" = "$r1_got" ] && [ "$r1_mode" = "755" ] \
     && [ "$r1_w1" -ge 1 ] && [ "$r1_w2" -ge 1 ] && [ "$r1_rows" -eq 1 ] && [ "$r1_path" = ".git/hooks/pre-commit" ]; then
    pass "R1: a re-add restores the archived file byte-identically at its recorded mode, prints the warning near-verbatim, and writes exactly one adoption_event/collision_re_add row naming the path"
  else
    fail_ "R1" "rc=$READD_RC want_sha=$r1_want got_sha=$r1_got mode=$r1_mode (want 755) warning_part1=$r1_w1 warning_part2=$r1_w2 rows=$r1_rows (want 1) path='$r1_path'"
  fi

  # R3 — the confirmation is MANDATORY. No answer means no re-add and no row.
  #
  # THE REFUSAL MUST BE THE RIGHT REFUSAL. Measured during this suite's
  # watched-RED run, with `--re-add` not yet a flag: the driver exited 2 on
  # "unrecognised option", the file was untouched, no row was written, and R3
  # PASSED — a green assertion that a feature refuses correctly, produced by
  # the feature not existing. So the transcript must carry the driver's own
  # mandatory-question refusal, spelled here independently of the source.
  R3="$(newtmp)"
  R3_REFUSAL="This question has no default and no skip, and no answer was given:"
  printf '#!/usr/bin/env bash\n# replaced again\nexit 0\n' > "$R1/p/.git/hooks/pre-commit"
  r3_before="$(_sha "$R1/p/.git/hooks/pre-commit")"
  r3_rows_before=$(jq -r '[.[] | select(.type == "adoption_event")] | length' "$R1/p/.claude/bypass-audit.json" 2>/dev/null); r3_rows_before=$(_num "$r3_rows_before")
  : > "$R3/confirm"
  run_readd "$R1/p" ".git/hooks/pre-commit" "$R3/confirm"
  r3_after="$(_sha "$R1/p/.git/hooks/pre-commit")"
  r3_rows_after=$(jq -r '[.[] | select(.type == "adoption_event")] | length' "$R1/p/.claude/bypass-audit.json" 2>/dev/null); r3_rows_after=$(_num "$r3_rows_after")
  r3_why=$(_count_in "$READD_ERR" "$R3_REFUSAL")
  if [ "$READD_RC" -ne 0 ] && [ "$r3_why" -ge 1 ] && [ "$r3_before" = "$r3_after" ] \
     && [ "$r3_rows_after" -eq "$r3_rows_before" ] && [ "$r3_rows_before" -ge 1 ]; then
    pass "R3: an unanswered confirmation refuses the re-add (rc $READD_RC) FOR THAT REASON — the file is untouched and no new audit row joins the $r3_rows_before already there"
  else
    fail_ "R3" "rc=$READD_RC (want non-zero) refused-for-the-mandatory-question=$r3_why (want >=1) sha before=$r3_before after=$r3_after rows before=$r3_rows_before (want >=1) after=$r3_rows_after"
  fi
fi

# ── R2 — MUTATION: suppress the re-add audit row -> a SILENT re-add ─────────
R2="$(newtmp)"
if ! mk_adoptee "$R2/p" || ! _add_surfaces "$R2/p" || ! mk_mirror "$R2/fw"; then
  fail_ "R2 (MUTATION)" "fixture setup failed"
else
  _ans > "$R2/answers"
  run_adopt "$R2/p" "$R2/answers" "$R2/fw"
  r2_arch="$(arch_dir_of "$R2/p")"
  MUTR="$R2/fw/scripts/lib/adopt/adopt-archive.sh"
  r2_sites=$(_sites "$L_ARCHIVE" 'BF-ADOPT-READD-AUDIT')
  cp "$L_ARCHIVE" "$R2/orig.ref"
  _sed_inplace "$MUTR" 's|^.*BF-ADOPT-READD-AUDIT$|  :   # BF-ADOPT-READD-AUDIT|'
  r2_chg=$(_changed_lines "$R2/orig.ref" "$MUTR")
  r2_parses=$(_parses "$MUTR")
  printf '#!/usr/bin/env bash\n# replaced\nexit 0\n' > "$R2/p/.git/hooks/pre-commit"
  r2_want="$(_sha "$R2/p/$r2_arch/git-hooks/pre-commit")"
  printf '1\n' > "$R2/confirm"
  run_readd "$R2/p" ".git/hooks/pre-commit" "$R2/confirm" "$R2/fw"
  r2_got="$(_sha "$R2/p/.git/hooks/pre-commit")"
  r2_rows=$(jq -r '[.[] | select(.type == "adoption_event") | select(.details.event == "collision_re_add")] | length' "$R2/p/.claude/bypass-audit.json" 2>/dev/null); r2_rows=$(_num "$r2_rows")
  # THE FILE MUST HAVE BEEN RESTORED. A mutant that died before doing anything
  # leaves the same "no row" state a correct refusal does; asserting the bytes
  # is what makes this a SILENT RE-ADD rather than an early exit.
  if [ "$r2_sites" -eq 1 ] && [ "$r2_chg" -eq 2 ] && [ "$r2_parses" -eq 1 ] \
     && [ -n "$r2_want" ] && [ "$r2_want" = "$r2_got" ] && [ "$r2_rows" -eq 0 ]; then
    pass "R2 (MUTATION): with the audit row suppressed (1 site, 2 lines, mutant parses) the re-add STILL HAPPENS — the file is restored byte-identically and the ledger records nothing. A silent re-add — RED"
  else
    fail_ "R2" "sites=$r2_sites (want 1) changed_lines=$r2_chg (want 2) parses=$r2_parses (want 1) restored_sha=$r2_got want=$r2_want rows=$r2_rows (want 0)"
  fi
fi

# ── R4 (R-WP6-4) — a re-add that CANNOT be recorded must not happen ─────────
#
# The R2 mutation forbids a silent re-add by sed. This one forbids the same
# thing AT RUNTIME, which is the version an operator can actually hit:
# `bypass_audit_append` returns 1 on a corrupt ledger (its jq filter fails) or
# on a lock timeout. Before this fix the driver ignored that rc and printed
# "The choice is recorded in .claude/bypass-audit.json" regardless — a false
# claim in the one artifact the re-add's legitimacy rests on.
#
# The ledger is corrupted rather than mocked, because the real failure is the
# real jq refusing real garbage.
R4="$(newtmp)"
if ! mk_adoptee "$R4/p" || ! _add_surfaces "$R4/p"; then
  fail_ "R4" "fixture setup failed"
else
  _ans > "$R4/answers"
  run_adopt "$R4/p" "$R4/answers"
  r4_arch="$(arch_dir_of "$R4/p")"
  printf '#!/usr/bin/env bash\n# replaced\nexit 0\n' > "$R4/p/.git/hooks/pre-commit"
  r4_before="$(_sha "$R4/p/.git/hooks/pre-commit")"
  printf 'this is not json at all\n' > "$R4/p/.claude/bypass-audit.json"
  printf '1\n' > "$R4/confirm"
  run_readd "$R4/p" ".git/hooks/pre-commit" "$R4/confirm"
  r4_rc=$READD_RC
  r4_after="$(_sha "$R4/p/.git/hooks/pre-commit")"
  # The false claim must be ABSENT, and the refusal must name the real cause.
  r4_falseclaim=$(_count_in "$READD_OUT" "The choice is recorded")
  r4_loud=$(_count_in "$READD_ERR" "could not be recorded")
  if [ "$r4_rc" -ne 0 ] && [ -n "$r4_before" ] && [ "$r4_before" = "$r4_after" ] \
     && [ "$r4_falseclaim" -eq 0 ] && [ "$r4_loud" -ge 1 ]; then
    pass "R4 (R-WP6-4): with the ledger corrupt the re-add REFUSES (rc $r4_rc) and does NOT restore the file — no row, no re-add, and the 'choice is recorded' claim is never printed"
  else
    fail_ "R4" "rc=$r4_rc (want non-zero) sha before=$r4_before after=$r4_after (want equal — the file must NOT be restored) false 'recorded' claim printed=$r4_falseclaim (want 0) refusal names the cause=$r4_loud (want >=1)"
  fi
fi

# ── R5 (R-WP6-12) — a re-add that fails BEFORE the copy leaves no row ───────
#
# The record-before-restore fix (R-WP6-4) buys "no re-add without a row" and
# costs a documented over-record: a failure between the row and the copy leaves
# a row describing something that did not happen. That window had TWO
# statements in it, not one — the `mkdir -p` as well as the `cp` — and only the
# `cp` was disclosed. The mkdir governs nothing the archive owns, so it belongs
# ABOVE the record, which shrinks the window to the `cp` alone and makes the
# documented residual the true one.
#
# Forced by making the parent path un-creatable: a regular FILE where the
# restore needs a directory.
R5="$(newtmp)"
if ! mk_adoptee "$R5/p" || ! _add_surfaces "$R5/p"; then
  fail_ "R5" "fixture setup failed"
else
  _ans > "$R5/answers"
  run_adopt "$R5/p" "$R5/answers"
  r5_rows_before=$(jq -r '[.[] | select(.details.event == "collision_re_add")] | length' "$R5/p/.claude/bypass-audit.json" 2>/dev/null); r5_rows_before=$(_num "$r5_rows_before")
  rm -rf "$R5/p/.claude/skills"
  printf 'a file where a directory needs to be\n' > "$R5/p/.claude/skills"
  printf '1\n' > "$R5/confirm"
  run_readd "$R5/p" ".claude/skills/invoice-helper/SKILL.md" "$R5/confirm"
  r5_rc=$READD_RC
  r5_rows_after=$(jq -r '[.[] | select(.details.event == "collision_re_add")] | length' "$R5/p/.claude/bypass-audit.json" 2>/dev/null); r5_rows_after=$(_num "$r5_rows_after")
  r5_isfile=0; [ -f "$R5/p/.claude/skills" ] && r5_isfile=1
  if [ "$r5_rc" -ne 0 ] && [ "$r5_isfile" -eq 1 ] && [ "$r5_rows_after" -eq "$r5_rows_before" ]; then
    pass "R5 (R-WP6-12): a re-add that cannot create its parent directory refuses (rc $r5_rc) and writes NO row — the mkdir sits above the record, so the documented over-record window is the cp alone"
  else
    fail_ "R5" "rc=$r5_rc (want non-zero) blocking file still present=$r5_isfile (want 1) re-add rows before=$r5_rows_before after=$r5_rows_after (want equal — a row here would mean the record ran before a step that failed)"
  fi
fi

echo ""
echo "=== G — the operator's .gitignore is an instruction, not a hint ==="

# THE PRIVATE PAYLOAD IS DELIBERATELY NOT SECRET-SHAPED.
# `internal-proxy.corp.example` matches no gitleaks rule — verified by G1's own
# `findingCount == 0` assertion. That is what makes G1 a test of the IGNORE
# rule rather than an accidental second test of the scanner: if the scanner
# could catch this, the withhold would be attributable to the wrong arm and the
# mutation could not isolate anything.
PRIVATE_PAYLOAD="internal-proxy.corp.example-jdoe"

# ── G1 (R-WP6-1) — a gitignored ORIGINAL is never committed under a new name ─
#
# The exposure this case exists for: the operator wrote
# `.claude/settings.local.json` in their .gitignore — an explicit statement
# that this CONTENT must never enter history — and the archive copied it to
# `.claude/adoption-archive/<dir>/.claude/settings.local.json`, a path the
# ANCHORED rule cannot match. Asking `git check-ignore` about the NEW path
# answers a question nobody asked. Verified hermetically: anchored rule vs
# original -> ignored; vs archive copy -> NOT ignored.
G1="$(newtmp)"
G1_OK=0
if mk_adoptee "$G1/p" && _add_surfaces "$G1/p" && _add_local_settings "$G1/p" "$PRIVATE_PAYLOAD"; then
  # TWO RULES, AND THE SECOND ONE IS THE ONE THAT BITES (R-WP6-10).
  #
  # `.git/` is a cargo-cult line real repositories commonly carry. It reaches
  # NO framework-written path, so it looks inert — and it is not. Measured
  # hermetically: `git check-ignore` applies patterns to any pathname it is
  # handed, `.git/` paths INCLUDED. `*`, `hooks/` and `.git/` all report
  # `.git/hooks/pre-commit` as IGNORED (rc 0). The earlier claim that
  # "`.git/hooks/*` is not reported as ignored because git excludes `.git/` by
  # construction" was a property of THE ANCHORED PATTERN in this fixture, not
  # of git — and G1b, testing only that anchored rule, structurally could not
  # see it. With this line present and no exemption, adoption completes at
  # rc 0 while silently withholding the hooks: §7.3's carrier and the archive's
  # whole point, withheld under an instruction git itself would never honour.
  printf '.claude/settings.local.json\n.git/\n' > "$G1/p/.gitignore"
  ( cd "$G1/p" && git add .gitignore && git commit -q -m "chore: their ignore rules" ) >/dev/null 2>&1
  _ans > "$G1/answers"
  run_adopt "$G1/p" "$G1/answers"
  G1_OK=1
fi
if [ "$G1_OK" -ne 1 ]; then
  fail_ "G1" "fixture setup failed"
  fail_ "G1b" "fixture setup failed"
else
  g1_arch="$(arch_dir_of "$G1/p")"
  g1_mj="$G1/p/$g1_arch/MANIFEST.json"
  g1_staged=$(jq -r '.entries[] | select(.originalPath == ".claude/settings.local.json") | .stagedForCommit' "$g1_mj" 2>/dev/null)
  g1_reason=$(jq -r '.entries[] | select(.originalPath == ".claude/settings.local.json") | .withheldReason // ""' "$g1_mj" 2>/dev/null)
  g1_landed=$(_adoption_commit_landed "$G1/p")
  g1_inhead=$(_in_head "$G1/p" "$g1_arch/.claude/settings.local.json")
  # THE PROBE CONTROLS. The archive copy on disk MUST hold the payload (the
  # copy really happened and the probe can see it), the committed-tree probe
  # MUST be able to find something that IS committed, and the scanner MUST
  # have found nothing — so the withhold is the ignore rule's doing.
  g1_ondisk=$(_count_in "$G1/p/$g1_arch/.claude/settings.local.json" "$PRIVATE_PAYLOAD")
  g1_ctrl=$( cd "$G1/p" && git grep -F -l -- "acme-api" HEAD 2>/dev/null | grep -c . ); g1_ctrl=$(_num "$g1_ctrl")
  g1_tree=$( cd "$G1/p" && git grep -F -l -- "$PRIVATE_PAYLOAD" HEAD 2>/dev/null | grep -c . ); g1_tree=$(_num "$g1_tree")
  g1_findings=$(jq -r '.secretsScan.findingCount // "null"' "$g1_mj" 2>/dev/null)
  g1_sib=$(_in_head "$G1/p" "$g1_arch/.claude/settings.json")
  if [ "$RUN_RC" -eq 0 ] && [ "$g1_landed" -eq 1 ] && [ "$g1_staged" = "false" ] \
     && [ "$g1_reason" = "original-gitignored" ] && [ "$g1_inhead" -eq 0 ] \
     && [ "$g1_ondisk" -ge 1 ] && [ "$g1_ctrl" -ge 1 ] && [ "$g1_tree" -eq 0 ] \
     && [ "$g1_findings" = "0" ] && [ "$g1_sib" -eq 1 ]; then
    pass "G1 (R-WP6-1): a file the operator gitignored is archived but NEVER committed under its new name — withheldReason=original-gitignored, absent from HEAD, and its payload is in 0 committed files while present in the archive copy. The scanner found $g1_findings, so the ignore rule is what saved it"
  else
    fail_ "G1" "rc=$RUN_RC landed=$g1_landed stagedForCommit='$g1_staged' (want false) withheldReason='$g1_reason' (want original-gitignored) in HEAD=$g1_inhead (want 0) payload in archive copy=$g1_ondisk (want >=1) tree probe control=$g1_ctrl (want >=1) payload in committed tree=$g1_tree (want 0) findingCount='$g1_findings' (want 0 — a non-zero count would mean the SCANNER caught it and this proves nothing about the ignore rule) clean sibling in HEAD=$g1_sib (want 1)"
  fi

  # G1b — THE BOUND, now tested against a pattern that actually reaches.
  #
  # THE PROBE CONTROL IS THE POINT OF THIS VERSION. The fixture's `.git/` rule
  # must genuinely make `git check-ignore` report the hook as IGNORED —
  # asserted below — or this case is back to testing the anchored rule, which
  # cannot reach `.git/` paths and therefore proved nothing about the bound.
  # That is precisely how the false claim survived a full review round.
  g1b_reaches=1
  ( cd "$G1/p" && git check-ignore -q -- ".git/hooks/pre-commit" ) 2>/dev/null || g1b_reaches=0
  g1b_hook_staged=$(jq -r '.entries[] | select(.originalPath == ".git/hooks/pre-commit") | .stagedForCommit' "$g1_mj" 2>/dev/null)
  g1b_hook_reason=$(jq -r '.entries[] | select(.originalPath == ".git/hooks/pre-commit") | .withheldReason // ""' "$g1_mj" 2>/dev/null)
  g1b_hook_head=$(_in_head "$G1/p" "$g1_arch/git-hooks/pre-commit")
  if [ "$g1b_reaches" -eq 1 ] && [ "$g1b_hook_staged" = "true" ] \
     && [ -z "$g1b_hook_reason" ] && [ "$g1b_hook_head" -eq 1 ]; then
    pass "G1b (the bound, R-WP6-10): the fixture's '.git/' rule DOES make check-ignore report the hook ignored (probe=$g1b_reaches), and the hooks are still archived AND committed anyway — a gitignore statement about a .git/ path is not an instruction git can honour, so the arm must not act on it"
  else
    fail_ "G1b" "fixture rule reaches .git/hooks/pre-commit=$g1b_reaches (want 1 — else this case tests nothing) hook stagedForCommit='$g1b_hook_staged' (want true) withheldReason='$g1b_hook_reason' (want empty) hook in HEAD=$g1b_hook_head (want 1)"
  fi
fi

# ── G1c — MUTATION: neuter the .git/* exemption ─────────────────────────────
G1C="$(newtmp)"
if ! mk_adoptee "$G1C/p" || ! _add_surfaces "$G1C/p" || ! mk_mirror "$G1C/fw"; then
  fail_ "G1c (MUTATION)" "fixture setup failed"
else
  printf '.git/\n' > "$G1C/p/.gitignore"
  ( cd "$G1C/p" && git add .gitignore && git commit -q -m "chore: their ignore rules" ) >/dev/null 2>&1
  MUTGC="$G1C/fw/scripts/lib/adopt/adopt-archive.sh"
  g1c_sites=$(_sites "$L_ARCHIVE" 'BF-ADOPT-GITDIR-EXEMPT')
  cp "$L_ARCHIVE" "$G1C/orig.ref"
  _sed_inplace "$MUTGC" 's|^.*BF-ADOPT-GITDIR-EXEMPT$|  case "$rel" in .git/*) : ;; esac   # BF-ADOPT-GITDIR-EXEMPT|'
  g1c_chg=$(_changed_lines "$G1C/orig.ref" "$MUTGC")
  g1c_parses=$(_parses "$MUTGC")
  _ans > "$G1C/answers"
  run_adopt "$G1C/p" "$G1C/answers" "$G1C/fw"
  g1c_arch="$(arch_dir_of "$G1C/p")"
  g1c_mj="$G1C/p/$g1c_arch/MANIFEST.json"
  g1c_reason=$(jq -r '.entries[] | select(.originalPath == ".git/hooks/pre-commit") | .withheldReason // ""' "$g1c_mj" 2>/dev/null)
  g1c_head=$(_in_head "$G1C/p" "$g1c_arch/git-hooks/pre-commit")
  g1c_landed=$(_adoption_commit_landed "$G1C/p")
  if [ "$g1c_sites" -eq 1 ] && [ "$g1c_chg" -eq 2 ] && [ "$g1c_parses" -eq 1 ] \
     && [ "$g1c_reason" = "original-gitignored" ] && [ "$g1c_head" -eq 0 ] && [ "$g1c_landed" -eq 1 ]; then
    pass "G1c (MUTATION): with the .git/* exemption neutered (1 site, 2 lines, mutant parses) an inert '.git/' line silently withholds the hooks (reason=original-gitignored, absent from HEAD) while adoption still reports success — RED"
  else
    fail_ "G1c" "sites=$g1c_sites (want 1) changed_lines=$g1c_chg (want 2) parses=$g1c_parses (want 1) hook withheldReason='$g1c_reason' (want original-gitignored) hook in HEAD=$g1c_head (want 0) adoption landed=$g1c_landed (want 1)"
  fi
fi

# ── G6 (R-WP6-11) — a corrupt ledger must not be committed in silence ───────
#
# The re-add treats "recorded" as a precondition; the archive's own row did not
# check the rc at all. Measured before the fix: adoption completed rc 0, the
# row was dropped without a word, and the STILL-CORRUPT ledger was committed
# into HEAD as the project's first governance record.
#
# The asymmetry with the re-add is deliberate and is not silence: the archive
# has a primary committed record (the MANIFEST), so a failed row degrades it
# rather than invalidating it. What it must not do is degrade quietly.
G6="$(newtmp)"
if ! mk_adoptee "$G6/p" || ! _add_surfaces "$G6/p"; then
  fail_ "G6" "fixture setup failed"
else
  mkdir -p "$G6/p/.claude"
  printf 'this is not json at all\n' > "$G6/p/.claude/bypass-audit.json"
  _ans > "$G6/answers"
  run_adopt "$G6/p" "$G6/answers"
  g6_rc=$RUN_RC
  g6_landed=$(_adoption_commit_landed "$G6/p")
  g6_arch="$(arch_dir_of "$G6/p")"
  g6_manifest=0
  [ -n "$g6_arch" ] && g6_manifest=$(_in_head "$G6/p" "$g6_arch/MANIFEST.json")
  g6_ledger=$(_in_head "$G6/p" ".claude/bypass-audit.json")
  g6_loud=$(_count_in "$RUN_OUT" "could not be recorded")
  if [ "$g6_rc" -eq 0 ] && [ "$g6_landed" -eq 1 ] && [ "$g6_manifest" -eq 1 ] \
     && [ "$g6_ledger" -eq 0 ] && [ "$g6_loud" -ge 1 ]; then
    pass "G6 (R-WP6-11): with the ledger already corrupt the adoption still completes (rc 0) and the MANIFEST still commits, but the failed audit row is announced LOUDLY and the corrupt ledger is kept OUT of the commit"
  else
    fail_ "G6" "rc=$g6_rc (want 0) landed=$g6_landed (want 1) MANIFEST in HEAD=$g6_manifest (want 1) corrupt ledger in HEAD=$g6_ledger (want 0) failure announced=$g6_loud (want >=1)"
  fi
fi

# ── G2 (R-WP6-2) — the archive-path arm, which had NO test at all ───────────
#
# `git-hooks/` is chosen precisely because it reaches the ARCHIVE COPY and NOT
# the original: the original is `.git/hooks/pre-commit`, whose directory is
# `hooks`, not `git-hooks`. So this case exercises the archive-path arm ALONE
# and cannot be satisfied by G1's original-path arm.
G2="$(newtmp)"
G2_OK=0
if mk_adoptee "$G2/p" && _add_surfaces "$G2/p"; then
  printf 'git-hooks/\n' > "$G2/p/.gitignore"
  ( cd "$G2/p" && git add .gitignore && git commit -q -m "chore: their ignore rules" ) >/dev/null 2>&1
  _ans > "$G2/answers"
  run_adopt "$G2/p" "$G2/answers"
  G2_OK=1
fi
if [ "$G2_OK" -ne 1 ]; then
  fail_ "G2" "fixture setup failed"
else
  g2_arch="$(arch_dir_of "$G2/p")"
  g2_mj="$G2/p/$g2_arch/MANIFEST.json"
  g2_reason=$(jq -r '.entries[] | select(.originalPath == ".git/hooks/pre-commit") | .withheldReason // ""' "$g2_mj" 2>/dev/null)
  g2_staged=$(jq -r '.entries[] | select(.originalPath == ".git/hooks/pre-commit") | .stagedForCommit' "$g2_mj" 2>/dev/null)
  g2_landed=$(_adoption_commit_landed "$G2/p")
  g2_head=$(_in_head "$G2/p" "$g2_arch/git-hooks/pre-commit")
  g2_manifest=$(_in_head "$G2/p" "$g2_arch/MANIFEST.json")
  g2_sib=$(_in_head "$G2/p" "$g2_arch/.claude/settings.json")
  # The ORIGINAL must not be ignored, or this case would be indistinguishable
  # from G1 and would pass on the wrong arm.
  g2_orig_ign=1
  ( cd "$G2/p" && git check-ignore -q -- ".git/hooks/pre-commit" ) 2>/dev/null || g2_orig_ign=0
  if [ "$RUN_RC" -eq 0 ] && [ "$g2_landed" -eq 1 ] && [ "$g2_staged" = "false" ] \
     && [ "$g2_reason" = "gitignored" ] && [ "$g2_head" -eq 0 ] \
     && [ "$g2_orig_ign" -eq 0 ] && [ "$g2_manifest" -eq 1 ] && [ "$g2_sib" -eq 1 ]; then
    pass "G2 (R-WP6-2): an ignore rule that reaches only the ARCHIVE COPY withholds that entry (withheldReason=gitignored) while the run completes rc 0 and the MANIFEST and clean sibling still commit — the original is NOT ignored, so this is the archive-path arm and no other"
  else
    fail_ "G2" "rc=$RUN_RC landed=$g2_landed stagedForCommit='$g2_staged' (want false) withheldReason='$g2_reason' (want gitignored) entry in HEAD=$g2_head (want 0) original ignored=$g2_orig_ign (want 0 — else this is G1's arm) MANIFEST in HEAD=$g2_manifest (want 1) sibling in HEAD=$g2_sib (want 1)"
  fi
fi

# ── G3 — MUTATION for R-WP6-1: neuter the ORIGINAL-path check ───────────────
G3="$(newtmp)"
if ! mk_adoptee "$G3/p" || ! _add_surfaces "$G3/p" || ! _add_local_settings "$G3/p" "$PRIVATE_PAYLOAD" || ! mk_mirror "$G3/fw"; then
  fail_ "G3 (MUTATION)" "fixture setup failed"
else
  printf '.claude/settings.local.json\n' > "$G3/p/.gitignore"
  ( cd "$G3/p" && git add .gitignore && git commit -q -m "chore: their ignore rules" ) >/dev/null 2>&1
  MUTG="$G3/fw/scripts/lib/adopt/adopt-archive.sh"
  g3_sites=$(_sites "$L_ARCHIVE" 'BF-ADOPT-IGNORE-ORIGINAL')
  cp "$L_ARCHIVE" "$G3/orig.ref"
  _sed_inplace "$MUTG" 's|^.*BF-ADOPT-IGNORE-ORIGINAL$|    elif false; then   # BF-ADOPT-IGNORE-ORIGINAL|'
  g3_chg=$(_changed_lines "$G3/orig.ref" "$MUTG")
  g3_parses=$(_parses "$MUTG")
  _ans > "$G3/answers"
  run_adopt "$G3/p" "$G3/answers" "$G3/fw"
  g3_arch="$(arch_dir_of "$G3/p")"
  g3_head=$(_in_head "$G3/p" "$g3_arch/.claude/settings.local.json")
  g3_tree=$( cd "$G3/p" && git grep -F -l -- "$PRIVATE_PAYLOAD" HEAD 2>/dev/null | grep -c . ); g3_tree=$(_num "$g3_tree")
  if [ "$g3_sites" -eq 1 ] && [ "$g3_chg" -eq 2 ] && [ "$g3_parses" -eq 1 ] \
     && [ "$g3_head" -eq 1 ] && [ "$g3_tree" -ge 1 ]; then
    pass "G3 (MUTATION): with the original-path check neutered (1 site, 2 lines, mutant parses) the gitignored file's copy IS committed and its private payload appears in $g3_tree committed file(s) — RED"
  else
    fail_ "G3" "sites=$g3_sites (want 1) changed_lines=$g3_chg (want 2) parses=$g3_parses (want 1) copy in HEAD=$g3_head (want 1) payload in tree=$g3_tree (want >=1)"
  fi
fi

# ── G4 — MUTATION for R-WP6-2: neuter the ARCHIVE-path check ────────────────
#
# Its observable is different from G3's and that difference is the arm's whole
# purpose: `git add` on an ignored path FAILS, and the driver stages every
# recorded path in ONE command, so removing this guard does not leak anything —
# it takes the entire adoption down. Asserted as an exit code AND as the
# absence of an adoption commit, with the archive on disk proving the run got
# that far rather than falling over earlier.
G4="$(newtmp)"
if ! mk_adoptee "$G4/p" || ! _add_surfaces "$G4/p" || ! mk_mirror "$G4/fw"; then
  fail_ "G4 (MUTATION)" "fixture setup failed"
else
  printf 'git-hooks/\n' > "$G4/p/.gitignore"
  ( cd "$G4/p" && git add .gitignore && git commit -q -m "chore: their ignore rules" ) >/dev/null 2>&1
  MUTG4="$G4/fw/scripts/lib/adopt/adopt-archive.sh"
  g4_sites=$(_sites "$L_ARCHIVE" 'BF-ADOPT-IGNORE-ARCHIVE')
  cp "$L_ARCHIVE" "$G4/orig.ref"
  _sed_inplace "$MUTG4" 's|^.*BF-ADOPT-IGNORE-ARCHIVE$|    elif false; then   # BF-ADOPT-IGNORE-ARCHIVE|'
  g4_chg=$(_changed_lines "$G4/orig.ref" "$MUTG4")
  g4_parses=$(_parses "$MUTG4")
  _ans > "$G4/answers"
  run_adopt "$G4/p" "$G4/answers" "$G4/fw"
  g4_rc=$RUN_RC
  g4_landed=$(_adoption_commit_landed "$G4/p")
  g4_arch="$(arch_dir_of "$G4/p")"
  g4_ondisk=0; [ -n "$g4_arch" ] && [ -f "$G4/p/$g4_arch/MANIFEST.json" ] && g4_ondisk=1
  if [ "$g4_sites" -eq 1 ] && [ "$g4_chg" -eq 2 ] && [ "$g4_parses" -eq 1 ] \
     && [ "$g4_rc" -ne 0 ] && [ "$g4_landed" -eq 0 ] && [ "$g4_ondisk" -eq 1 ]; then
    pass "G4 (MUTATION): with the archive-path check neutered (1 site, 2 lines, mutant parses) git add refuses the ignored path and the WHOLE adoption fails (rc $g4_rc, no adoption commit) — the archive is on disk, so the run reached staging — RED"
  else
    fail_ "G4" "sites=$g4_sites (want 1) changed_lines=$g4_chg (want 2) parses=$g4_parses (want 1) run rc=$g4_rc (want non-zero) adoption commit landed=$g4_landed (want 0) archive on disk=$g4_ondisk (want 1)"
  fi
fi

# ── G5 — the operator may ignore the ARCHIVE ITSELF, and adoption survives ──
# `.claude/adoption-archive/` is a plausible thing to gitignore: it is a local
# backup directory. It reaches every entry AND both MANIFEST files, so the
# MANIFEST's own staging has to go through the same guard — otherwise the one
# unconditional `adopt_record_write` pair takes the adoption down.
G5="$(newtmp)"
if ! mk_adoptee "$G5/p" || ! _add_surfaces "$G5/p"; then
  fail_ "G5" "fixture setup failed"
else
  printf '.claude/adoption-archive/\n' > "$G5/p/.gitignore"
  ( cd "$G5/p" && git add .gitignore && git commit -q -m "chore: their ignore rules" ) >/dev/null 2>&1
  _ans > "$G5/answers"
  run_adopt "$G5/p" "$G5/answers"
  g5_rc=$RUN_RC
  g5_landed=$(_adoption_commit_landed "$G5/p")
  g5_arch="$(arch_dir_of "$G5/p")"
  g5_mj=""; [ -n "$g5_arch" ] && g5_mj="$G5/p/$g5_arch/MANIFEST.json"
  g5_ondisk=0; [ -n "$g5_mj" ] && [ -f "$g5_mj" ] && g5_ondisk=1
  g5_staged=$(jq -r '[.entries[] | select(.stagedForCommit == true)] | length' "$g5_mj" 2>/dev/null); g5_staged=$(_num "$g5_staged")
  g5_manifest=0
  [ -n "$g5_arch" ] && g5_manifest=$(_in_head "$G5/p" "$g5_arch/MANIFEST.json")
  g5_disclosed=0
  [ -n "$g5_arch" ] && g5_disclosed=$(_count_in "$RUN_OUT" "$g5_arch")
  if [ "$g5_rc" -eq 0 ] && [ "$g5_landed" -eq 1 ] && [ "$g5_ondisk" -eq 1 ] \
     && [ "$g5_staged" -eq 0 ] && [ "$g5_manifest" -eq 0 ] && [ "$g5_disclosed" -ge 1 ]; then
    pass "G5: an operator who gitignores the archive directory still gets a COMPLETED adoption (rc 0) — nothing archive-shaped is committed, including the MANIFEST, and the archive is still on disk and still disclosed on screen"
  else
    fail_ "G5" "rc=$g5_rc (want 0) landed=$g5_landed (want 1) MANIFEST on disk=$g5_ondisk (want 1) entries staged=$g5_staged (want 0) MANIFEST in HEAD=$g5_manifest (want 0) archive named in transcript=$g5_disclosed (want >=1)"
  fi
fi

echo ""
echo "=== E — adoption_event across §8.9's five surfaces ==="

# Surface 1 — the type enum docblock in scripts/lib/bypass-audit.sh.
e1=$(_count_in "$BYPASS_LIB" "adoption_event")
if [ "$e1" -ge 1 ]; then
  pass "E1 (surface 1/5): the type enum docblock in scripts/lib/bypass-audit.sh names adoption_event"
else
  fail_ "E1" "occurrences in the docblock=$e1 (want >=1)"
fi

# Surface 2 — §8.9's second surface is PRESENT in test-bl029-integration.sh.
#
# WHAT THIS CASE CLAIMS, NARROWED (R-WP6-8). It is a PRESENCE check: the type
# is named in that file and that file writes a row with the real emitter. Its
# earlier wording claimed the pin "can make it fail", which this case cannot
# show — its whitelist half is a BRE whose second alternative
# (`adoption_event.*)`) is satisfied by T4b's own fail-message text, so the
# whitelist could be gone and this would stay green. The falsifiability claim
# belongs to E6, which runs the REAL extracted predicate against a mutated
# emitter, and to tests/test-bl029-integration.sh itself, which goes to
# 7 passed / 1 failed when adoption_event is dropped from the whitelist.
# Overlapping coverage is fine; an overstated claim is not.
e2_case=$(grep -c 'adoption_event' "$BL029" 2>/dev/null); e2_case=$(_num "$e2_case")
e2_white=0
grep -q '|adoption_event)' "$BL029" 2>/dev/null && e2_white=1
e2_fixture=0
grep -q 'adopt_audit_event' "$BL029" 2>/dev/null && e2_fixture=1
if [ "$e2_case" -ge 2 ] && [ "$e2_white" -eq 1 ] && [ "$e2_fixture" -eq 1 ]; then
  pass "E2 (surface 2/5, PRESENCE): adoption_event is a case-arm alternative in T6's whitelist and test-bl029-integration.sh writes such a row with the real emitter. Falsifiability is E6's and bl029's own, not this case's"
else
  fail_ "E2" "adoption_event mentions in test-bl029=$e2_case (want >=2) present as a '|adoption_event)' case alternative=$e2_white writes a row via the real emitter=$e2_fixture"
fi

# Surface 3 — the emitter, marked, with exactly one site.
e3_sites=$(_sites "$L_ARCHIVE" 'BF-ADOPT-AUDIT-ROW')
e3_fn=0
grep -q '^adopt_audit_event()' "$L_ARCHIVE" 2>/dev/null && e3_fn=1
if [ "$e3_sites" -eq 1 ] && [ "$e3_fn" -eq 1 ]; then
  pass "E3 (surface 3/5): the emitter adopt_audit_event exists and its type literal is marked at exactly one site"
else
  fail_ "E3" "marked sites=$e3_sites (want 1) function present=$e3_fn"
fi

# Surface 4 — a consumer that puts the type in a ledger and ASSERTS on it.
# R1 above is that consumer; E4 checks the row is schema-valid, because a row
# that no reader can parse is not a record.
E4="$(newtmp)"
e4_ok=0
if [ "$R1_OK" -eq 1 ]; then
  e4_row=$(jq -r '[.[] | select(.type == "adoption_event")] | .[0]' "$R1/p/.claude/bypass-audit.json" 2>/dev/null)
  printf '%s\n' "$e4_row" > "$E4/row.json"
  jq -e '(.type == "adoption_event")
         and (.actor == "framework")
         and ((.timestamp // "") != "")
         and ((.enforcement_level_at_event // "") | test("^(no|light|strict|n/a)$"))
         and ((.user_response // "") | test("^(PENDING|accepted|declined|n/a)$"))
         and ((.final_outcome // "") | test("^(committed|bypassed|escalated|abandoned|recorded_only|n/a)$"))
         and ((.details.event // "") != "")' "$E4/row.json" >/dev/null 2>&1 && e4_ok=1
fi
if [ "$e4_ok" -eq 1 ]; then
  pass "E4 (surface 4/5): the emitted row satisfies the documented BL-030 schema — actor, enforcement level, user_response and final_outcome are all inside their enums, and details.event discriminates"
else
  fail_ "E4" "row=[$(head -c 300 "$E4/row.json" 2>/dev/null | tr '\n' ' ')]"
fi

# Surface 5 — docs/audit-log-lifecycle.md's taxonomy AND a cold-pickup recipe
# that is EXECUTED against a real ledger. A recipe nobody runs is prose.
e5_tax=0
grep -q '^### `adoption_event`' "$LIFECYCLE_DOC" 2>/dev/null && e5_tax=1
e5_recipe="$(grep -F "select(.type == \"adoption_event\")" "$LIFECYCLE_DOC" 2>/dev/null | grep '^jq ' | head -1)"
e5_ran=0; e5_hits=0
if [ -n "$e5_recipe" ] && [ "$R1_OK" -eq 1 ]; then
  e5_out="$( cd "$R1/p" && eval "$e5_recipe" 2>/dev/null )"
  e5_ran=1
  e5_hits=$(printf '%s' "$e5_out" | grep -c 'collision_re_add'); e5_hits=$(_num "$e5_hits")
fi
if [ "$e5_tax" -eq 1 ] && [ "$e5_ran" -eq 1 ] && [ "$e5_hits" -ge 1 ]; then
  pass "E5 (surface 5/5): the lifecycle doc carries an adoption_event section, and its cold-pickup jq recipe RUNS against a real ledger and returns the re-add row"
else
  fail_ "E5" "taxonomy section=$e5_tax recipe found and run=$e5_ran rows returned=$e5_hits recipe=[$e5_recipe]"
fi

# ── E6 — MUTATION: the T6 pin can actually go RED ──────────────────────────
# The whole point of §8.9's fourth surface. The REAL T6 predicate is EXTRACTED
# from tests/test-bl029-integration.sh (never re-typed here, which would only
# prove that a copy agrees with itself) and run over two ledgers built by the
# emitter: the shipped one, and one whose type literal has been mutated.
E6="$(newtmp)"
e6_pred="$E6/t6.sh"
sed -n '/^TYPES=/,/^done$/p' "$BL029" > "$E6/t6-body" 2>/dev/null
e6_extract=0
grep -q 'case "$t" in' "$E6/t6-body" 2>/dev/null && e6_extract=1
{
  printf 'PROJ="$1"\n'
  cat "$E6/t6-body"
  printf '[ "$TYPE_OK" = "1" ]\n'
} > "$e6_pred"

_e6_ledger() {
  local libdir="$1" out="$2"
  mkdir -p "$out/.claude"
  printf '[]\n' > "$out/.claude/bypass-audit.json"
  ( . "$REPO_ROOT/scripts/lib/bypass-audit.sh" >/dev/null 2>&1
    . "$libdir/adopt-archive.sh" >/dev/null 2>&1
    adopt_audit_event "$out" "collision_re_add" '{"path":".git/hooks/pre-commit"}' ) >/dev/null 2>&1
}

e6_good_rc=0; e6_bad_rc=0; e6_good_rows=0; e6_bad_rows=0
if [ "$e6_extract" -eq 1 ] && mk_mirror "$E6/fw"; then
  _e6_ledger "$LIB_DIR" "$E6/good"
  e6_good_rows=$(jq -r 'length' "$E6/good/.claude/bypass-audit.json" 2>/dev/null); e6_good_rows=$(_num "$e6_good_rows")
  bash "$e6_pred" "$E6/good" >/dev/null 2>&1 || e6_good_rc=$?

  MUTE="$E6/fw/scripts/lib/adopt/adopt-archive.sh"
  e6_sites=$(_sites "$L_ARCHIVE" 'BF-ADOPT-AUDIT-ROW')
  cp "$L_ARCHIVE" "$E6/orig.ref"
  _sed_inplace "$MUTE" 's|^.*BF-ADOPT-AUDIT-ROW$|  _ae_type="adoption_evnt"   # BF-ADOPT-AUDIT-ROW|'
  e6_chg=$(_changed_lines "$E6/orig.ref" "$MUTE")
  e6_parses=$(_parses "$MUTE")
  _e6_ledger "$E6/fw/scripts/lib/adopt" "$E6/bad"
  e6_bad_rows=$(jq -r 'length' "$E6/bad/.claude/bypass-audit.json" 2>/dev/null); e6_bad_rows=$(_num "$e6_bad_rows")
  bash "$e6_pred" "$E6/bad" >/dev/null 2>&1 || e6_bad_rc=$?
else
  e6_sites=0; e6_chg=0; e6_parses=0
fi
if [ "$e6_extract" -eq 1 ] && [ "$e6_sites" -eq 1 ] && [ "$e6_chg" -eq 2 ] && [ "$e6_parses" -eq 1 ] \
   && [ "$e6_good_rows" -eq 1 ] && [ "$e6_bad_rows" -eq 1 ] \
   && [ "$e6_good_rc" -eq 0 ] && [ "$e6_bad_rc" -ne 0 ]; then
  pass "E6 (MUTATION): the REAL T6 predicate, extracted from test-bl029-integration.sh, accepts the shipped emitter's row (rc 0) and REJECTS a one-character type drift (rc $e6_bad_rc) — the whitelist pin can go red"
else
  fail_ "E6" "extracted=$e6_extract sites=$e6_sites (want 1) changed_lines=$e6_chg (want 2) parses=$e6_parses rows good=$e6_good_rows bad=$e6_bad_rows (both want 1) predicate rc good=$e6_good_rc (want 0) bad=$e6_bad_rc (want non-zero)"
fi

echo ""
echo "=== C — the collision archive is recorded, and the module stays severable ==="

# C1 — the archive itself is an audit EVENT (§8.9's fourth row: "every
# collision archive"), not only a printed disclosure.
c1_rows=$(jq -r '[.[] | select(.type == "adoption_event") | select(.details.event == "collision_archive")] | length' "$A_D/p/.claude/bypass-audit.json" 2>/dev/null); c1_rows=$(_num "$c1_rows")
c1_dir=$(jq -r '[.[] | select(.type == "adoption_event") | select(.details.event == "collision_archive")] | .[0].details.archiveDir // ""' "$A_D/p/.claude/bypass-audit.json" 2>/dev/null)
c1_count=$(jq -r '[.[] | select(.type == "adoption_event") | select(.details.event == "collision_archive")] | .[0].details.entryCount // -1' "$A_D/p/.claude/bypass-audit.json" 2>/dev/null); c1_count=$(_num "$c1_count")
# AND THE LEDGER IS IN THE COMMIT. A row that exists only in an untracked file
# is a record no clone carries — docs/audit-log-lifecycle.md calls this the
# TRACKED ledger, and an adopted project must get the same thing a scaffolded
# one does.
c1_ledger=$(_in_head "$A_D/p" ".claude/bypass-audit.json")
if [ "$c1_rows" -eq 1 ] && [ "$c1_dir" = "$A_ARCH" ] && [ "$c1_count" -ge 4 ] && [ "$c1_ledger" -eq 1 ]; then
  pass "C1: the collision archive writes exactly one adoption_event/collision_archive row naming the directory and its $c1_count entries — and the ledger carrying it is IN the adoption commit"
else
  fail_ "C1" "rows=$c1_rows (want 1) archiveDir='$c1_dir' (want $A_ARCH) entryCount=$c1_count (want >=4) ledger in HEAD=$c1_ledger (want 1)"
fi

# C1b — the same, with the operator's .gitignore excluding the ledger: the run
# must NOT abort. `git add` on an ignored path fails, and the driver stages
# every recorded path in one command, so an unguarded record here would take
# the whole adoption down. Positive control built in: the adoption commit must
# still land and the archive's own MANIFEST must still be in it.
C1B="$(newtmp)"
if ! mk_adoptee "$C1B/p" || ! _add_surfaces "$C1B/p"; then
  fail_ "C1b" "fixture setup failed"
else
  printf '.claude/bypass-audit.json\n' > "$C1B/p/.gitignore"
  ( cd "$C1B/p" && git add .gitignore && git commit -q -m "chore: their ignore rules" ) >/dev/null 2>&1
  _ans > "$C1B/answers"
  run_adopt "$C1B/p" "$C1B/answers"
  c1b_rc=$RUN_RC
  c1b_landed=$(_adoption_commit_landed "$C1B/p")
  c1b_arch="$(arch_dir_of "$C1B/p")"
  c1b_ledger=$(_in_head "$C1B/p" ".claude/bypass-audit.json")
  c1b_manifest=0
  [ -n "$c1b_arch" ] && c1b_manifest=$(_in_head "$C1B/p" "$c1b_arch/MANIFEST.json")
  c1b_ondisk=0; [ -f "$C1B/p/.claude/bypass-audit.json" ] && c1b_ondisk=1
  if [ "$c1b_rc" -eq 0 ] && [ "$c1b_landed" -eq 1 ] && [ "$c1b_ledger" -eq 0 ] \
     && [ "$c1b_manifest" -eq 1 ] && [ "$c1b_ondisk" -eq 1 ]; then
    pass "C1b: when the operator's .gitignore excludes the ledger the adoption still COMPLETES (rc 0) — the ledger is on disk and out of the commit, and the archive MANIFEST still lands"
  else
    fail_ "C1b" "rc=$c1b_rc (want 0) adoption commit landed=$c1b_landed (want 1) ledger in HEAD=$c1b_ledger (want 0) ledger on disk=$c1b_ondisk (want 1) MANIFEST in HEAD=$c1b_manifest (want 1)"
  fi
fi

# C2 — M3: no CORE file may name this module. Run the real lint.
c2_rc=0
( cd "$REPO_ROOT" && bash scripts/lint-module-dependencies.sh ) >"$TOPTMP/mod.out" 2>&1 || c2_rc=$?
if [ "$c2_rc" -eq 0 ]; then
  pass "C2: scripts/lint-module-dependencies.sh is rc 0 — no core file references the adoption module"
else
  fail_ "C2" "lint rc=$c2_rc: $(tail -5 "$TOPTMP/mod.out" | tr '\n' ' ')"
fi

# C3 — the driver's declared core-dependency header (M2) names bypass-audit.sh,
# which WP6 adds. An undeclared source line is an M2 violation that no lint
# catches today, so the declaration is asserted here.
c3=0
grep -q 'bypass-audit\.sh' "$DRIVER" 2>/dev/null && c3=1
if [ "$c3" -eq 1 ]; then
  pass "C3 (M2): the driver's declared core-dependency list names scripts/lib/bypass-audit.sh"
else
  fail_ "C3" "the M2 header does not declare the bypass-audit dependency this package adds"
fi

echo ""
if [ "$SKIPPED" -gt 0 ] && [ "$GITLEAKS_ABSENT_IS_FATAL" -eq 1 ]; then
  echo "  [FAIL] CI GUARD — $SKIPPED case(s) skipped for a missing gitleaks. In CI that is a"
  echo "         proof that did not run, on the property whose failure mode is a committed"
  echo "         credential. Install gitleaks in the workflow or fix the install step."
  FAILED=$((FAILED + 1))
fi

echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]

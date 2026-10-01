#!/usr/bin/env bash
# tests/test-bl313-ci-before-manifest.sh
#
# `## BL-313:` — A GENERATED GITHUB CI WORKFLOW MUST BE GREEN BEFORE THE
# LANGUAGE MANIFEST EXISTS, AND MUST NOT BE WEAKENED ONCE IT DOES.
#
# Every ci/github/<lang>.yml opens its `test` job with a toolchain that
# assumes the language manifest is already committed: setup-node with
# `cache: 'npm'` (which fails hard — "Dependencies lock file is not found" —
# before `npm ci` even runs), `pip install -r requirements.txt`, `./gradlew
# build`, `dotnet restore`, `flutter pub get`, `go build`, `cargo build`,
# `swift package resolve`. A project born from init.sh has none of those
# files until Phase 2, so the `test` check is red on every pull request the
# operator opens in Phase 0 and 1 — the intake, the manifesto, every
# approval-log row. Measured 2026-09-22 on a project scaffolded from
# f8841de: the setup-node step failed at 00:57:19Z with that exact error and
# the job never reached a `run:` step.
#
# The fix guards every manifest-dependent step with the template's own
# idiom — `if: hashFiles('<manifest>') != ''`, already used on the three
# governance steps — and adds ONE notice step (`== ''`) that says what was
# skipped and why. hashFiles returns '' when nothing matches (GitHub Actions
# expressions reference), so the guards are false on an empty tree and true
# the moment the manifest lands; nothing that exists today is weakened, and
# a package.json committed WITHOUT its lockfile still fails setup-node loudly,
# which is the correct verdict under the framework's pin-and-commit rule.
#
# CASES — all on the real tree, `test` job only (the `sast` job scans the
# tree and needs no manifest):
#   T0  the template list is derived (find), meets a floor of 10 (9 language templates plus other.yml), and every
#       template has a census row — a new language cannot slip in unguarded
#   T1  exactly one notice step per template, guarded `== ''` on the census
#       manifest, and its body carries a `::notice::` annotation
#   T2  every toolchain step — everything that is not checkout, not the
#       notice, not the secret scan and not `Governance -` — is guarded
#       `!= ''` on the same manifest; floor of 3 such steps per template
#   T3  checkout and the gitleaks secret scan are NOT guarded, and no
#       governance step's own guard names the manifest (the fix must not
#       turn a Phase-0 tree into an unscanned one)
#   T4  a shell evaluation of the guards: over an EMPTY fixture every
#       toolchain step skips and the notice runs; with the first census
#       sample file present every toolchain step runs and the notice skips.
#       This evaluates the `hashFiles(<patterns>) != ''` / `== ''` forms the
#       templates carry, and nothing else — `act` is not available here, so
#       the workflow itself is not executed; the assertion is on the
#       rendered YAML plus this evaluation of its conditions.
#   T5  past Phase 1 a missing manifest FAILS, it does not skip green: the
#       notice step's `run:` script is extracted and EXECUTED under
#       `"$BASH" -e -o pipefail` (stricter than the runner's default `bash -e {0}`, under the
#       interpreter this suite itself runs under) against four
#       fixtures — `.claude/phase-state.json` at current_phase 3 and 2
#       (rc 1, `::error::`), at current_phase 1 (rc 0, `::notice::`), and
#       no phase-state at all (rc 0, `::notice::`). A review of the first
#       cut found the gap: a Poetry or Pipenv project (the framework's own
#       Python guidance) has no requirements.txt, and on a Phase 3 tree
#       every toolchain step skipped and the check went green — "a check
#       that cannot run must not pass".
#   T6  one case per language: every manifest name in the census, placed
#       ALONE in a fixture, enables every toolchain step and skips the
#       notice. The census carries the manifests the harness itself
#       recognises (process-checklist.sh's lockfile list and the platform
#       modules' lockfile notes), so a compliant project is never
#       "manifest absent".
# MUTANTS (on a mirror of templates/, never the real tree): remove one
# guard, invert one guard, guard the secret scan, delete the notice step,
# delete the phase check's `exit 1`, drop one manifest name from every
# guard of one template. Each proves it landed (changed-line count) and
# names the case that fails.
#
# WHY `other.yml` IS OUT: its toolchain steps are TODO comments and its
# dependency-audit step exits 1 by design until the operator configures a
# scanner — there is no manifest to guard on and the red is deliberate.
#
# The census below is the SPEC, in bl254's documented-census idiom — it is
# not derived from the templates, because a manifest read off the file it
# is meant to check would agree with itself. Row format:
#   <lang>|<hashFiles argument list, verbatim>|<sample files, one per pattern, space-separated>
# The first sample is what T4 uses; T6 uses each in turn.
#
# REGISTRATION: content-pin only — no init.sh on any executed line, not an
# aggregator -> BOTH tests/full-project-test-suite.sh and the tests.yml
# unit list. Hermetic: reads tracked files, writes only under mktemp.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GH_DIR="$REPO_ROOT/templates/pipelines/ci/github"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/fixXXXXXX"; }

_num() { case "$1" in ''|null|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$1" ;; esac }
_changed_lines() {
  local n=""
  n=$(diff "$1" "$2" 2>/dev/null | grep -c '^[<>]')
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s\n' "$n"
}
# count_in <file> <fixed-string> — occurrences, never a pipe (no SIGPIPE under pipefail)
count_in() { local n=""; n=$(grep -cF -- "$2" "$1" 2>/dev/null); _num "$n"; }

CENSUS_FILE="$TOPTMP/census.txt"
cat > "$CENSUS_FILE" <<'EOF'
typescript|'package.json'|package.json
python|'requirements.txt', 'pyproject.toml', 'Pipfile'|requirements.txt pyproject.toml Pipfile
java|'**/*.gradle*', '**/pom.xml'|build.gradle.kts pom.xml
kotlin|'**/*.gradle*', '**/pom.xml'|build.gradle.kts pom.xml
go|'go.mod'|go.mod
rust|'Cargo.toml'|Cargo.toml
csharp|'**/*.sln', '**/*.csproj'|App.sln App.csproj
dart|'pubspec.yaml'|pubspec.yaml
swift|'Package.swift'|Package.swift
EOF
census_args()    { awk -F'|' -v l="$1" '$1==l {print $2; exit}' "$CENSUS_FILE"; }
census_samples() { awk -F'|' -v l="$1" '$1==l {print $3; exit}' "$CENSUS_FILE"; }
census_sample()  { local s=""; s="$(census_samples "$1")"; printf '%s\n' "${s%% *}"; }

# template_list <github-templates-dir> — the ONE derivation every case uses:
# regular *.yml files directly in the directory, sorted, dotfiles excluded.
# A first cut used find here and a `*.yml` glob in the gap walker; an
# AppleDouble `._x.yml` sidecar (macOS tar into a container) was then counted
# by one and skipped by the other, and the tallies disagreed. One list.
template_list() {
  find "$1" -maxdepth 1 -type f -name '*.yml' ! -name '.*' 2>/dev/null | LC_ALL=C sort
}

# steps_of <template> — one line per step of the `test` job:
#   <name-or-uses>\t<if-expression or ->\t<1 if the body carries ::notice::>
# Scoped to the `test` job (indent-2 key) so the `sast` job's steps never
# enter the census; a step opens at indent-6 `- `, its `if:` sits at indent 8.
steps_of() {
  awk '
    function flush() { if (name != "") print name "\t" cond "\t" note; name = "" }
    BEGIN { injob = 0; name = ""; cond = "-"; note = 0 }
    /^  test:[[:space:]]*$/ { injob = 1; next }
    injob && /^  [A-Za-z_][A-Za-z0-9_-]*:/ { flush(); injob = 0 }
    injob && /^      - / {
      flush()
      name = $0
      sub(/^      - (name|uses):[[:space:]]*/, "", name)
      cond = "-"; note = 0
      next
    }
    injob && /^        if:[[:space:]]/ { cond = $0; sub(/^        if:[[:space:]]*/, "", cond) }
    injob && /::notice::/ { note = 1 }
    END { flush() }
  ' "$1"
}

# notice_script <template> <want-skip-cond> — the `run: |` block of the step
# whose `if:` is <want-skip-cond>, de-indented (the block sits at indent 10),
# so T5 can EXECUTE it. Empty output if the step or its block is absent.
notice_script() {
  awk -v want="$2" '
    BEGIN { instep = 0; inrun = 0 }
    /^      - / { instep = 0; inrun = 0 }
    /^        if:[[:space:]]/ { c = $0; sub(/^        if:[[:space:]]*/, "", c); if (c == want) instep = 1 }
    instep && /^        run:[[:space:]]*\|[[:space:]]*$/ { inrun = 1; next }
    instep && inrun && /^          / { line = $0; sub(/^          /, "", line); print line; next }
    instep && inrun && /^[[:space:]]*$/ { next }
    instep && inrun { inrun = 0 }
  ' "$1"
}

# run_notice <script-file> <fixture-root> — executes the notice script the way
# the runner does (`-e -o pipefail`, cwd = the checked-out tree) under THIS
# suite's interpreter (`$BASH`), so the version the suite is run with is the
# version the subject runs under — PATH bash would silently be another one.
# Prints "<rc> <annotation kind>", the kind being error, notice, or none.
run_notice() {
  local rc=0 out="" kind="none"
  out="$(cd "$2" && "$BASH" -e -o pipefail "$1" 2>&1)" || rc=$?
  case "$out" in
    *"::error::"*)  kind="error" ;;
    *"::notice::"*) kind="notice" ;;
  esac
  printf '%s %s\n' "$rc" "$kind"
}

# manifest_gaps <github-templates-dir> — one line per violation:
#   <file>: <class>: <detail>
# classes: census-missing notice-count notice-manifest notice-text
#          guard-missing guard-wrong toolchain-floor checkout-guarded
#          gitleaks-guarded governance-manifest
manifest_gaps() {
  local d="$1" f="" lang="" args="" want_run="" want_skip="" steps="" name="" cond="" note=""
  local n_notice=0 n_tool=0 short="" list=""
  list="$TOPTMP/gaps.list.$$"
  template_list "$d" > "$list"
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    lang="${f##*/}"; lang="${lang%.yml}"
    [ "$lang" = "other" ] && continue
    args="$(census_args "$lang")"
    if [ -z "$args" ]; then
      printf '%s: census-missing: no census row for language %s\n' "$lang.yml" "$lang"
      continue
    fi
    want_run="hashFiles($args) != ''"
    want_skip="hashFiles($args) == ''"
    steps="$TOPTMP/steps.$lang.$$"
    steps_of "$f" > "$steps"
    n_notice=0; n_tool=0
    while IFS="$(printf '\t')" read -r name cond note; do
      short="${name%% #*}"
      case "$name" in
        actions/checkout@*)
          [ "$cond" = "-" ] || printf '%s: checkout-guarded: checkout carries if: %s\n' "$lang.yml" "$cond" ;;
        'Security - Secret detection (gitleaks)')
          [ "$cond" = "-" ] || printf '%s: gitleaks-guarded: secret scan carries if: %s\n' "$lang.yml" "$cond" ;;
        'Governance - '*)
          case "$cond" in
            *"$args"*) printf '%s: governance-manifest: %s is guarded on the manifest (%s)\n' "$lang.yml" "$short" "$cond" ;;
          esac ;;
        *)
          if [ "$cond" = "$want_skip" ]; then
            n_notice=$((n_notice + 1))
            [ "$note" = "1" ] || printf '%s: notice-text: the skip step (%s) prints no ::notice:: annotation\n' "$lang.yml" "$short"
          elif [ "$cond" = "$want_run" ]; then
            n_tool=$((n_tool + 1))
          elif [ "$cond" = "-" ]; then
            printf '%s: guard-missing: %s has no if: guard\n' "$lang.yml" "$short"
          else
            case "$cond" in
              *"== ''"*) printf '%s: notice-manifest: a skip step (%s) is guarded on %s, not on %s\n' "$lang.yml" "$short" "$cond" "$want_skip" ;;
              *)         printf '%s: guard-wrong: %s carries if: %s, expected %s\n' "$lang.yml" "$short" "$cond" "$want_run" ;;
            esac
          fi ;;
      esac
    done < "$steps"
    [ "$n_notice" -eq 1 ] || printf '%s: notice-count: %s skip step(s) guarded %s, expected exactly 1\n' "$lang.yml" "$n_notice" "$want_skip"
    [ "$n_tool" -ge 3 ]   || printf '%s: toolchain-floor: only %s guarded toolchain step(s), floor 3\n' "$lang.yml" "$n_tool"
  done < "$list"
}

# hf_nonempty <root> <hashFiles-args> — rc 0 iff any file under <root> matches
# any pattern in the argument list. The list is what the templates carry:
# single-quoted literals, comma-separated. A leading `**/` means any depth;
# anything else is a path from the root. This is the only form evaluated.
hf_nonempty() {
  local root="$1" rest="$2" pat="" hit=""
  while [ -n "$rest" ]; do
    pat="${rest%%,*}"
    if [ "$pat" = "$rest" ]; then rest=""; else rest="${rest#*,}"; fi
    pat="${pat#"${pat%%[! ]*}"}"
    pat="${pat#\'}"; pat="${pat%\'}"
    case "$pat" in
      '**/'*)
        hit="$(find "$root" -type f -name "${pat#\*\*/}" -print 2>/dev/null | head -1)"
        [ -n "$hit" ] && return 0 ;;
      *) [ -f "$root/$pat" ] && return 0 ;;
    esac
  done
  return 1
}

# eval_guard <root> <if-expression> — prints run|skip|unknown
eval_guard() {
  local root="$1" cond="$2" args=""
  case "$cond" in
    -) printf 'run\n'; return ;;
    "hashFiles("*") != ''")
      args="${cond#hashFiles(}"; args="${args%) != \'\'}"
      if hf_nonempty "$root" "$args"; then printf 'run\n'; else printf 'skip\n'; fi ;;
    "hashFiles("*") == ''")
      args="${cond#hashFiles(}"; args="${args%) == \'\'}"
      if hf_nonempty "$root" "$args"; then printf 'skip\n'; else printf 'run\n'; fi ;;
    *) printf 'unknown\n' ;;
  esac
}

# simulate <template> <lang> <root> — prints "<tool_run> <tool_skip> <notice_verdict> <unknown>"
simulate() {
  local f="$1" lang="$2" root="$3" args="" want_skip="" steps="" name="" cond="" note="" v=""
  local tr=0 ts=0 nv="absent" unk=0
  args="$(census_args "$lang")"
  want_skip="hashFiles($args) == ''"
  steps="$TOPTMP/sim.$lang.$$"
  steps_of "$f" > "$steps"
  while IFS="$(printf '\t')" read -r name cond note; do
    case "$name" in
      actions/checkout@*|'Security - Secret detection (gitleaks)'|'Governance - '*) continue ;;
    esac
    v="$(eval_guard "$root" "$cond")"
    if [ "$cond" = "$want_skip" ]; then
      nv="$v"
    else
      case "$v" in run) tr=$((tr + 1)) ;; skip) ts=$((ts + 1)) ;; *) unk=$((unk + 1)) ;; esac
    fi
  done < "$steps"
  printf '%s %s %s %s\n' "$tr" "$ts" "$nv" "$unk"
}

# mk_mirror <dir> — templates/ only; enough for every function above
mk_mirror() {
  mkdir -p "$1" || return 1
  cp -Rp "$REPO_ROOT/templates" "$1/" || return 1
  return 0
}

echo "=== T — the invariants on the real tree ==="

# T0 — derived list, floor, census coverage
GH_LIST="$TOPTMP/gh.txt"
template_list "$GH_DIR" > "$GH_LIST"
n_gh=$(_num "$(grep -c . "$GH_LIST")")
n_lang=$((n_gh - 1))
if [ "$n_gh" -ge 10 ]; then
  pass "T0 — $n_gh github CI templates found (floor 10 incl. other.yml)"
else
  fail_ "T0" "found $n_gh github CI templates, expected >=10 — the derivation is vacuous"
fi
census_miss=""
while IFS= read -r f; do
  lang="${f##*/}"; lang="${lang%.yml}"
  [ "$lang" = "other" ] && continue
  [ -n "$(census_args "$lang")" ] || census_miss="$census_miss $lang"
done < "$GH_LIST"
census_orphan=""
while IFS='|' read -r lang _ _; do
  [ -f "$GH_DIR/$lang.yml" ] || census_orphan="$census_orphan $lang"
done < "$CENSUS_FILE"
if [ -z "$census_miss" ] && [ -z "$census_orphan" ]; then
  pass "T0 — census covers every language template ($n_lang) and names no absent one"
else
  fail_ "T0" "census/template mismatch — templates without a row:${census_miss:- none}; rows without a template:${census_orphan:- none}"
fi

GAPS="$TOPTMP/gaps.txt"
manifest_gaps "$GH_DIR" > "$GAPS"

# T1 — the notice step
n_t1=$(( $(count_in "$GAPS" ': notice-count: ') + $(count_in "$GAPS" ': notice-manifest: ') + $(count_in "$GAPS" ': notice-text: ') ))
if [ "$n_t1" -eq 0 ]; then
  pass "T1 — every language template ($n_lang) carries exactly one ::notice:: skip step guarded == '' on its manifest"
else
  fail_ "T1" "$n_t1 notice violation(s): $(grep -E ': notice-(count|manifest|text): ' "$GAPS" | head -3 | tr '\n' ';' | cut -c1-240)"
fi

# T2 — every toolchain step guarded
n_t2=$(( $(count_in "$GAPS" ': guard-missing: ') + $(count_in "$GAPS" ': guard-wrong: ') + $(count_in "$GAPS" ': toolchain-floor: ') + $(count_in "$GAPS" ': census-missing: ') ))
n_guarded=0
while IFS= read -r f; do
  lang="${f##*/}"; lang="${lang%.yml}"
  [ "$lang" = "other" ] && continue
  args="$(census_args "$lang")"
  [ -n "$args" ] || continue
  steps_of "$f" > "$TOPTMP/t2.txt"
  n_guarded=$((n_guarded + $(count_in "$TOPTMP/t2.txt" "	hashFiles($args) != ''	")))
done < "$GH_LIST"
if [ "$n_t2" -eq 0 ]; then
  pass "T2 — every toolchain step is guarded != '' on its manifest ($n_guarded guarded steps across $n_lang templates)"
else
  fail_ "T2" "$n_t2 guard violation(s): $(grep -E ': (guard-missing|guard-wrong|toolchain-floor|census-missing): ' "$GAPS" | head -3 | tr '\n' ';' | cut -c1-240)"
fi

# T3 — nothing weakened: checkout, secret scan and governance stay unconditional on the manifest
n_t3=$(( $(count_in "$GAPS" ': checkout-guarded: ') + $(count_in "$GAPS" ': gitleaks-guarded: ') + $(count_in "$GAPS" ': governance-manifest: ') ))
if [ "$n_t3" -eq 0 ]; then
  pass "T3 — checkout, the gitleaks secret scan and the governance steps are not guarded on the manifest in any template"
else
  fail_ "T3" "$n_t3 weakening(s): $(grep -E ': (checkout-guarded|gitleaks-guarded|governance-manifest): ' "$GAPS" | head -3 | tr '\n' ';' | cut -c1-240)"
fi

# T4 — evaluate the guards over an empty tree and over a scaffolded one
t4_bad=""
t4_tool=0
while IFS= read -r f; do
  lang="${f##*/}"; lang="${lang%.yml}"
  [ "$lang" = "other" ] && continue
  [ -n "$(census_args "$lang")" ] || continue
  E="$(newtmp)"; M="$(newtmp)"
  sample="$(census_sample "$lang")"
  : > "$M/$sample"
  set -- $(simulate "$f" "$lang" "$E")
  e_run="$1"; e_skip="$2"; e_notice="$3"; e_unk="$4"
  set -- $(simulate "$f" "$lang" "$M")
  m_run="$1"; m_skip="$2"; m_notice="$3"; m_unk="$4"
  if [ "$e_run" -ne 0 ] || [ "$e_skip" -lt 3 ] || [ "$e_notice" != "run" ] || [ "$e_unk" -ne 0 ]; then
    t4_bad="$t4_bad $lang(empty:run=$e_run,skip=$e_skip,notice=$e_notice,unknown=$e_unk)"
  fi
  if [ "$m_skip" -ne 0 ] || [ "$m_run" -lt 3 ] || [ "$m_notice" != "skip" ] || [ "$m_unk" -ne 0 ]; then
    t4_bad="$t4_bad $lang(with-$sample:run=$m_run,skip=$m_skip,notice=$m_notice,unknown=$m_unk)"
  fi
  t4_tool=$((t4_tool + m_run))
done < "$GH_LIST"
if [ -z "$t4_bad" ]; then
  pass "T4 — over an empty tree every toolchain step skips and the notice runs; with the manifest present all $t4_tool toolchain steps run and the notice skips ($n_lang templates)"
else
  fail_ "T4" "guard evaluation disagrees with the intent:$t4_bad"
fi

# T5 — the notice step EXECUTED: past Phase 1 it fails, before it notices.
# mk_phase_fixture <dir> <phase|none>
mk_phase_fixture() {
  mkdir -p "$1/.claude" || return 1
  [ "$2" = "none" ] && return 0
  printf '{\n  "current_phase": %s,\n  "phase_gates": {}\n}\n' "$2" > "$1/.claude/phase-state.json"
}
# t5_check <template> <lang> — prints violations, one per line
t5_check() {
  local f="$1" lang="$2" args="" want_skip="" script="" fx="" v=""
  args="$(census_args "$lang")"
  want_skip="hashFiles($args) == ''"
  script="$TOPTMP/notice.$lang.$$.sh"
  notice_script "$f" "$want_skip" > "$script"
  if [ ! -s "$script" ]; then
    printf '%s: no run: | block on the notice step\n' "$lang.yml"; return
  fi
  if [ "$(count_in "$script" 'current_phase')" -lt 1 ] || [ "$(count_in "$script" 'exit 1')" -lt 1 ]; then
    printf '%s: notice script does not read current_phase and exit 1\n' "$lang.yml"
  fi
  fx="$(newtmp)"; mk_phase_fixture "$fx" 3
  v="$(run_notice "$script" "$fx")"
  [ "$v" = "1 error" ] || printf '%s: at current_phase 3 expected "1 error", got "%s"\n' "$lang.yml" "$v"
  fx="$(newtmp)"; mk_phase_fixture "$fx" 2
  v="$(run_notice "$script" "$fx")"
  [ "$v" = "1 error" ] || printf '%s: at current_phase 2 expected "1 error", got "%s"\n' "$lang.yml" "$v"
  fx="$(newtmp)"; mk_phase_fixture "$fx" 1
  v="$(run_notice "$script" "$fx")"
  [ "$v" = "0 notice" ] || printf '%s: at current_phase 1 expected "0 notice", got "%s"\n' "$lang.yml" "$v"
  fx="$(newtmp)"; mk_phase_fixture "$fx" none
  v="$(run_notice "$script" "$fx")"
  [ "$v" = "0 notice" ] || printf '%s: with no phase-state.json expected "0 notice", got "%s"\n' "$lang.yml" "$v"
}
t5_bad="$TOPTMP/t5.txt"; : > "$t5_bad"
while IFS= read -r f; do
  lang="${f##*/}"; lang="${lang%.yml}"
  [ "$lang" = "other" ] && continue
  [ -n "$(census_args "$lang")" ] || continue
  t5_check "$f" "$lang" >> "$t5_bad"
done < "$GH_LIST"
if [ ! -s "$t5_bad" ]; then
  pass "T5 — executed: every notice step exits 1 with ::error:: at current_phase 2 and 3, and exits 0 with ::notice:: at phase 1 or with no phase-state ($n_lang templates, 4 fixtures each)"
else
  fail_ "T5" "$(grep -c . "$t5_bad") violation(s): $(head -3 "$t5_bad" | tr '\n' ';' | cut -c1-240)"
fi

# T6 — one case per language: each census manifest name ALONE enables the toolchain.
while IFS= read -r f; do
  lang="${f##*/}"; lang="${lang%.yml}"
  [ "$lang" = "other" ] && continue
  [ -n "$(census_args "$lang")" ] || continue
  t6_bad=""; t6_n=0
  for sample in $(census_samples "$lang"); do
    M="$(newtmp)"; : > "$M/$sample"
    set -- $(simulate "$f" "$lang" "$M")
    t6_n=$((t6_n + 1))
    if [ "$2" -ne 0 ] || [ "$1" -lt 3 ] || [ "$3" != "skip" ] || [ "$4" -ne 0 ]; then
      t6_bad="$t6_bad $sample(run=$1,skip=$2,notice=$3,unknown=$4)"
    fi
  done
  if [ -z "$t6_bad" ]; then
    pass "T6-$lang — each of $t6_n manifest name(s) alone enables every toolchain step and skips the notice"
  else
    fail_ "T6-$lang" "a recognised manifest alone still skips the toolchain:$t6_bad"
  fi
done < "$GH_LIST"

echo "=== MT — mutation proofs on a mirror ==="

# MT1 — remove the guard from the setup-node step in typescript.yml: T2 must name it.
MT1="$(newtmp)/fw"
if ! mk_mirror "$MT1"; then
  fail_ "MT1 setup" "could not mirror the framework"
else
  tgt="$MT1/templates/pipelines/ci/github/typescript.yml"
  before="$(mktemp "$TOPTMP/mt1.XXXXXX")"; cp "$tgt" "$before"
  awk '
    /^      - uses: actions\/setup-node@/ { innode = 1; print; next }
    innode && /^        if: hashFiles\(.package\.json.\) != ..$/ { innode = 0; next }
    /^      - / { innode = 0 }
    { print }
  ' "$before" > "$tgt"
  if [ "$(_changed_lines "$before" "$tgt")" -ne 1 ]; then
    fail_ "MT1 setup" "the mutation did not remove exactly one line — the setup-node guard is not in the shape this suite expects"
  else
    manifest_gaps "$MT1/templates/pipelines/ci/github" > "$TOPTMP/mt1.gaps"
    if [ "$(count_in "$TOPTMP/mt1.gaps" 'typescript.yml: guard-missing: actions/setup-node@')" -ge 1 ]; then
      pass "MT1 (MUTATION) — with the setup-node guard removed, T2 names typescript.yml's setup-node step"
    else
      fail_ "MT1 (MUTATION)" "removing the guard changed nothing — T2 is not reading the step it claims to"
    fi
  fi
fi

# MT2 — invert one toolchain guard in go.yml (!= -> ==): T1 sees two notice
# steps and T2 sees one toolchain step fewer; either alone would be a
# different defect, so both are asserted.
MT2="$(newtmp)/fw"
if ! mk_mirror "$MT2"; then
  fail_ "MT2 setup" "could not mirror the framework"
else
  tgt="$MT2/templates/pipelines/ci/github/go.yml"
  before="$(mktemp "$TOPTMP/mt2.XXXXXX")"; cp "$tgt" "$before"
  awk '
    /^      - name: Build$/ { inbuild = 1; print; next }
    inbuild && /^        if: hashFiles\(.go\.mod.\) != ..$/ { sub(/ != /, " == "); inbuild = 0 }
    /^      - / { inbuild = 0 }
    { print }
  ' "$before" > "$tgt"
  if [ "$(_changed_lines "$before" "$tgt")" -ne 2 ]; then
    fail_ "MT2 setup" "the mutation did not flip exactly one line — go.yml's Build guard is not in the shape this suite expects"
  elif [ "$(count_in "$tgt" "hashFiles('go.mod') == ''")" -ne 2 ]; then
    fail_ "MT2 setup" "the flipped text did not land — expected two == '' guards in the mutant"
  else
    manifest_gaps "$MT2/templates/pipelines/ci/github" > "$TOPTMP/mt2.gaps"
    if [ "$(count_in "$TOPTMP/mt2.gaps" 'go.yml: notice-count: 2 skip step(s)')" -ge 1 ] \
       && [ "$(count_in "$TOPTMP/mt2.gaps" 'go.yml: notice-text: the skip step (Build)')" -ge 1 ]; then
      pass "MT2 (MUTATION) — with one go.yml guard inverted, T1 counts two skip steps and names Build as a skip step with no notice"
    else
      fail_ "MT2 (MUTATION)" "inverting a guard changed nothing T1 can see: $(head -3 "$TOPTMP/mt2.gaps" | tr '\n' ';')"
    fi
  fi
fi

# MT3 — guard the gitleaks secret scan on the manifest in python.yml: T3 must
# refuse it. This is the weakening the fix must never introduce: a Phase-0
# tree with a leaked credential and no requirements.txt would go unscanned.
MT3="$(newtmp)/fw"
if ! mk_mirror "$MT3"; then
  fail_ "MT3 setup" "could not mirror the framework"
else
  tgt="$MT3/templates/pipelines/ci/github/python.yml"
  before="$(mktemp "$TOPTMP/mt3.XXXXXX")"; cp "$tgt" "$before"
  awk '
    { print }
    /^      - name: Security - Secret detection \(gitleaks\)$/ { print "        if: hashFiles('"'"'requirements.txt'"'"') != '"'"''"'"'" }
  ' "$before" > "$tgt"
  if [ "$(_changed_lines "$before" "$tgt")" -ne 1 ]; then
    fail_ "MT3 setup" "the mutation did not add exactly one line"
  else
    manifest_gaps "$MT3/templates/pipelines/ci/github" > "$TOPTMP/mt3.gaps"
    if [ "$(count_in "$TOPTMP/mt3.gaps" 'python.yml: gitleaks-guarded: ')" -ge 1 ]; then
      pass "MT3 (MUTATION) — a manifest guard on the secret scan is refused by T3"
    else
      fail_ "MT3 (MUTATION)" "guarding the secret scan changed nothing — T3 would let a Phase-0 tree go unscanned"
    fi
  fi
fi

# MT4 — delete the notice step from rust.yml: T1 must count zero.
MT4="$(newtmp)/fw"
if ! mk_mirror "$MT4"; then
  fail_ "MT4 setup" "could not mirror the framework"
else
  tgt="$MT4/templates/pipelines/ci/github/rust.yml"
  before="$(mktemp "$TOPTMP/mt4.XXXXXX")"; cp "$tgt" "$before"
  # drop the step whose `if:` is the == '' guard: from its `- name:` line to the line before the next step
  awk '
    /^      - / { if (buf != "" && !drop) printf "%s", buf; buf = ""; drop = 0 }
    /^        if: hashFiles\(.Cargo\.toml.\) == ..$/ { drop = 1 }
    { buf = buf $0 "\n" }
    END { if (buf != "" && !drop) printf "%s", buf }
  ' "$before" > "$tgt"
  if [ "$(_changed_lines "$before" "$tgt")" -lt 3 ]; then
    fail_ "MT4 setup" "the mutation removed fewer than 3 lines — rust.yml's notice step is not in the shape this suite expects"
  elif [ "$(count_in "$tgt" "hashFiles('Cargo.toml') == ''")" -ne 0 ]; then
    fail_ "MT4 setup" "the == '' guard is still present in the mutant"
  else
    manifest_gaps "$MT4/templates/pipelines/ci/github" > "$TOPTMP/mt4.gaps"
    if [ "$(count_in "$TOPTMP/mt4.gaps" 'rust.yml: notice-count: 0 skip step(s)')" -ge 1 ]; then
      pass "MT4 (MUTATION) — with rust.yml's notice step deleted, T1 counts zero and names the file"
    else
      fail_ "MT4 (MUTATION)" "deleting the notice step changed nothing — T1 is not counting what it claims to"
    fi
  fi
fi

# MT5 — delete the phase check's `exit 1` from python.yml's notice step: T5
# must see rc 0 at phase 3 (the green-nobody-reads regression restored).
MT5="$(newtmp)/fw"
if ! mk_mirror "$MT5"; then
  fail_ "MT5 setup" "could not mirror the framework"
else
  tgt="$MT5/templates/pipelines/ci/github/python.yml"
  before="$(mktemp "$TOPTMP/mt5.XXXXXX")"; cp "$tgt" "$before"
  awk '
    /^        if: hashFiles\(.*\) == ..$/ { innotice = 1 }
    /^      - / { innotice = 0 }
    innotice && /^            exit 1$/ { innotice = 0; next }
    { print }
  ' "$before" > "$tgt"
  if [ "$(_changed_lines "$before" "$tgt")" -ne 1 ]; then
    fail_ "MT5 setup" "the mutation did not remove exactly one line — python.yml's notice step has no exit 1 at the expected indent"
  else
    t5_check "$tgt" python > "$TOPTMP/mt5.bad"
    if [ "$(count_in "$TOPTMP/mt5.bad" 'at current_phase 3 expected "1 error", got "0 error"')" -ge 1 ]; then
      pass "MT5 (MUTATION) — with the exit 1 deleted, T5 executes the notice at phase 3 and sees rc 0 — the regression is caught"
    else
      fail_ "MT5 (MUTATION)" "deleting exit 1 changed nothing T5 can see: $(head -2 "$TOPTMP/mt5.bad" | tr '\n' ';')"
    fi
  fi
fi

# MT6 — drop one recognised manifest name ('pyproject.toml') from EVERY guard
# of python.yml, self-consistently: T2 (guard-wrong against the census), T1
# (notice-manifest) and T6-python (pyproject.toml alone skips) must all fire.
MT6="$(newtmp)/fw"
if ! mk_mirror "$MT6"; then
  fail_ "MT6 setup" "could not mirror the framework"
else
  tgt="$MT6/templates/pipelines/ci/github/python.yml"
  before="$(mktemp "$TOPTMP/mt6.XXXXXX")"; cp "$tgt" "$before"
  sed "s#hashFiles('requirements.txt', 'pyproject.toml', 'Pipfile')#hashFiles('requirements.txt', 'Pipfile')#" "$before" > "$tgt"
  n_ch="$(_changed_lines "$before" "$tgt")"
  if [ "$n_ch" -lt 18 ]; then
    fail_ "MT6 setup" "the mutation changed $n_ch line(s), expected >=18 (9 guards, before and after) — python.yml's guards are not in the census shape"
  elif [ "$(count_in "$tgt" "'pyproject.toml'")" -ne 0 ]; then
    fail_ "MT6 setup" "'pyproject.toml' still present in the mutant"
  else
    manifest_gaps "$MT6/templates/pipelines/ci/github" > "$TOPTMP/mt6.gaps"
    M6="$(newtmp)"; : > "$M6/pyproject.toml"
    set -- $(simulate "$tgt" python "$M6")
    # The mutant's notice no longer matches the census condition, so the
    # simulator counts it among the toolchain (run=1); the eight real
    # toolchain steps must be the ones that SKIP on a pyproject.toml-only
    # tree — that skip is the regression, and it is what T6-python asserts.
    if [ "$(count_in "$TOPTMP/mt6.gaps" 'python.yml: guard-wrong: ')" -ge 1 ] \
       && [ "$(count_in "$TOPTMP/mt6.gaps" 'python.yml: notice-manifest: ')" -ge 1 ] \
       && [ "$2" -ge 3 ]; then
      pass "MT6 (MUTATION) — with pyproject.toml dropped from every python.yml guard, T2 and T1 name the drift and a pyproject.toml-only tree skips $2 toolchain steps again"
    else
      fail_ "MT6 (MUTATION)" "dropping a manifest name was not caught: gaps=$(grep -c . "$TOPTMP/mt6.gaps") sim=run=$1,skip=$2,notice=$3"
    fi
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] && exit 0
exit 1

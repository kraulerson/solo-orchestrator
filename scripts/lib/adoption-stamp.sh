#!/usr/bin/env bash
# scripts/lib/adoption-stamp.sh
#
# Brownfield adoption — THE IN-CORE ENABLING ARMS (design
# docs/designs/2026-08-02-brownfield-adoption-v1.md §3.1/§3.2, §8.5, §10-WP3).
#
# This file is CORE, not module code. §3.2 settles why the arms cannot live in
# an external kit: an outsider can only fake history, and a key nothing reads
# is not enforcement. The arms here are deliberately tiny — §10 calls WP3
# "three arms and a stamp" against a driver (WP4–WP7) that is most of the
# build. Nothing in this file sources module code, and nothing here knows the
# driver exists; the driver sources this, never the reverse (M3).
#
# Four things live here, and only four:
#   1. soif_adoption_adopted          — THE `adopted` flag accessor. One
#                                       function, one place, so every gate arm
#                                       reads the flag through a single surface
#                                       and a mutation proof has ONE thing to
#                                       neuter.
#   2. soif_adoption_stamp            — the writer. One additive jq merge,
#                                       EXACTLY the soif_currency_stamp filter
#                                       form, written ONCE at adoption from a
#                                       single call site in the driver. It is
#                                       NOT a backfill and must never become
#                                       one (the operating-model design's F1
#                                       correction on soif_currency_stamp:
#                                       birth-stamp-only, never a backfill
#                                       precedent).
#   3. soif_adoption_pre_adoption_commit — the BOUND the TDD arm honours.
#   4. soif_adoption_integrity_lost / _report_loss — the regenerate-path
#                                       detector.
#
# ── WHY THE MANIFEST, AND WHY A MERGE (§8.5, C2) ────────────────────────────
# The home is `.claude/manifest.json`'s top-level `adoption` block. The reason
# is merge-versus-re-stamp, NOT "the manifest has no wholesale writer" — that
# v1.0 rationale was REFUTED (§0.2 R-BF-1): fix_framework_manifest() delegates
# to the upstream CDF init script, which rewrites the manifest wholesale from a
# hardcoded key set carrying no Solo keys at all. BOTH state files have a
# regenerate-on-missing writer and neither location is categorically safe. What
# separates them: `phase-state.json` is additionally RE-STAMPED on every
# upgrade against a file that exists (`review_gate_enforced = True`,
# unconditional), while every writer that touches an EXISTING manifest is an
# additive merge — `.host = $h` (check-gate.sh, upgrade-project.sh),
# `. + {deployment, poc_mode, enforcement_level}` (the BL-030 backfill),
# `. + {deployment, poc_mode}` (the BL-061 refresh), and soif_currency_stamp's
# `.currency = $currency`.
#
# ── THE LOSS CANNOT BE PREVENTED (§12-12) ───────────────────────────────────
# The upstream manifest writer lives in a DIFFERENT REPOSITORY and is outside
# this design's control. When the manifest is lost to any cause and
# regenerated, the stamp is gone with it and the project silently becomes
# un-adopted. This file therefore does not pretend to prevent that. It DETECTS
# it and REPORTS IT LOUDLY, using the one witness that survives a wholesale
# rewrite of the working copy: the manifest is a TRACKED file, so the copy
# committed at HEAD still carries the block the working copy lost. The honest
# statement of the property: the design cannot stop the erasure, so it refuses
# to be quiet about it.
#
# The real assumption underneath, worth stating plainly (§12-12): that the
# upstream manifest writer stays MISSING-FILE-GATED. If it ever becomes
# unconditional, every adopted project un-adopts on the next repair run — and
# the detector here is what makes that visible on the very next gate.
#
# ── FORWARD DEPENDENCY FOR WP4 — READ THIS BEFORE SHIPPING THE DRIVER ───────
# `init.sh` copies `scripts/lib/` files into a scaffolded project BY EXPLICIT
# NAME, and THIS FILE IS NOT ON THAT LIST. Downstream that is harmless today:
# the gate copies guard their source with `[ -f … ]` and their calls with
# `command -v`, so every arm here no-ops and greenfield behaviour is unchanged
# (pinned by A2 and T5). But it means WP4's driver MUST ship
# `scripts/lib/adoption-stamp.sh` into the adoptee — otherwise every arm in
# this WP silently no-ops on the very projects it was built for, which is the
# same silence §12-12 is written against, arriving by a different door.
#
# bash-3.2 safe: no associative arrays, no `${var,,}`, no `[[ -v ]]`, no
# `((x++))` under set -e. Every helper is set -e safe — the return-1 arms are
# only ever reached through an `if` condition at the call sites.

# soif_adoption_read <manifest> <jq-filter> — thin jq -r reader over the block.
# Mirrors soif_currency_read. Empty output on any failure.
soif_adoption_read() {
  jq -r "$2" "$1" 2>/dev/null
}

# ── The committed witness (shared primitive) ────────────────────────────────
# _soif_adoption_head_copy_adopted [manifest] — 0 iff the copy of <manifest>
# COMMITTED AT HEAD records an adoption.
#
# ONE primitive, TWO consumers, and that is deliberate: the loss detector uses
# it to tell "the record was here and is gone" from "there was never a record",
# and the BOUND uses it to tell the adoption window from everything after it.
# Both questions are the same question — "has the adoption already landed in
# history?" — and answering it in one place means one thing to mutate and no
# second state file, so the dual-source ban holds.
#
# Returns non-zero both when HEAD's copy is NOT adopted and when the question
# cannot be answered at all (no jq, no git, off-root, never committed). The
# two consumers want opposite things from "cannot answer" and each says so at
# its own call site rather than pushing a third state through this one.
_soif_adoption_head_copy_adopted() {
  local manifest="${1:-.claude/manifest.json}"
  command -v jq >/dev/null 2>&1 || return 1
  git rev-parse --git-dir >/dev/null 2>&1 || return 1

  # Both halves of every comparison built on this must name the SAME file.
  # `git show HEAD:<p>` resolves <p> from the REPO ROOT while `[ -f <p> ]`
  # resolves it from the CWD; called from a subdirectory those are different
  # files, and the mismatch reads as "committed but missing from the working
  # tree" — a FALSE ALARM, the failure direction this repo has already paid for
  # twice (the false-FAIL doctrine behind BL-122/BL-149). `--show-prefix` is
  # empty only at the top level and, unlike comparing `--show-toplevel` to
  # $PWD, it is immune to symlinked temp roots.
  local prefix
  prefix="$(git rev-parse --show-prefix 2>/dev/null)" || return 1
  [ -z "$prefix" ] || return 1

  local head_copy
  head_copy="$(git show "HEAD:$manifest" 2>/dev/null)" || return 1
  [ -n "$head_copy" ] || return 1
  printf '%s' "$head_copy" | jq -e '.adoption.adopted == true' >/dev/null 2>&1 || return 1
  return 0
}

# ── 1. THE ACCESSOR ─────────────────────────────────────────────────────────
# soif_adoption_adopted [manifest] — returns 0 iff this project is ADOPTED.
#
# ABSENT FLAG ⇒ NOT ADOPTED, and that is load-bearing: a greenfield project
# must be unaffected by every arm in this WP. So a missing manifest, a manifest
# with no `adoption` block, `adopted: false`, malformed JSON, and a host with
# no jq ALL read NOT ADOPTED. The predicate fails CLOSED in the direction that
# leaves existing behaviour exactly as it was.
soif_adoption_adopted() {
  local manifest="${1:-.claude/manifest.json}"
  command -v jq >/dev/null 2>&1 || return 1
  [ -f "$manifest" ] || return 1
  jq -e '.adoption.adopted == true' "$manifest" >/dev/null 2>&1 || return 1   # BF-ADOPT-FLAG-READ
  return 0
}

# ── 2. THE STAMP ────────────────────────────────────────────────────────────
# soif_adoption_stamp <manifest> <scenario> <landed_phase> \
#                     <kindA_json> <kindB_json> <kindC_json> \
#                     <blockers_json> <scanner_report_sha256>
#
# Assembles §8.5's block and jq-merges it into <manifest> with the
# atomic-rename pattern, exactly as soif_currency_stamp does. Additive: every
# pre-existing manifest field is preserved.
#
# EXACTLY ONE CALL SITE, in the driver, marked. Written once, at adoption,
# never re-stamped. That call site DOES NOT EXIST YET and its absence is
# correct, not an oversight: WP3 ships the enabling arms and WP4 ships the
# driver that calls this. Until then the only callers are the WP3 suites. When
# the driver lands, ONE marked call is the whole budget — a second one turns a
# birth stamp into a backfill, which is the mistake soif_currency_stamp's own
# F1 correction exists to forbid.
#
# Two computed fields are NOT parameters, deliberately:
#   adoptedAt        — the stamp's own clock. A caller-supplied date is a
#                      caller-supplied lie waiting to happen.
#   adoptedAtCommit  — `git rev-parse HEAD` at stamp time: the PRE-ADOPTION
#                      TIP, i.e. the parent the adoption commit will land on.
#                      §8.5's content list is author-proposed and carries no
#                      commit anchor, but the TDD arm's BOUND is defined
#                      against the adoption commit and a bound needs an anchor.
#                      It is recorded HERE, in the stamp, and NOT read from
#                      `.claude/last-checked-commit.txt`: that file is the
#                      §8.7 detection baseline and the shipped
#                      `--reset-detection-baseline` operator surface rewrites
#                      it, which would silently MOVE the TDD exemption
#                      boundary. Two controls, two anchors.
#
# No-ops (rc 0, nothing written) when jq is unavailable or the manifest does
# not exist — the `[ -f "$manifest" ] || return 0` idiom. REFUSES (rc 1,
# nothing written) on a scenario outside §8.5's enum: a durable record that
# says how a project got here must not be written malformed.
soif_adoption_stamp() {
  local manifest="${1:-.claude/manifest.json}"
  local scenario="${2:-}"
  local landed_phase="${3:-0}"
  local kind_a="${4:-[]}" kind_b="${5:-[]}" kind_c="${6:-[]}"
  local blockers="${7:-[]}" scanner_sha="${8:-}"

  case "$scenario" in
    completed|in-flight) : ;;
    *) return 1 ;;   # BF-ADOPT-SCENARIO-ENUM
  esac
  case "$landed_phase" in ''|*[!0-9]*) landed_phase=0 ;; esac

  command -v jq >/dev/null 2>&1 || return 0
  [ -f "$manifest" ] || return 0

  # ENFORCE "written once, at adoption, never re-stamped" — do not merely
  # assert it in a header. Left unenforced, "one call site" is convention, and
  # a second stamp SILENTLY MOVES adoptedAtCommit to the current tip, which
  # re-opens the TDD exemption window at will; the loss detector cannot see it
  # because both copies read adopted. Refusing here makes the property
  # structural. If a driver ever needs a legitimate scenario transition, that is
  # a design amendment with its own function — not a silent overwrite.
  if jq -e '.adoption.adopted == true' "$manifest" >/dev/null 2>&1; then
    return 1   # BF-ADOPT-RESTAMP-REFUSE
  fi

  local adopted_at anchor
  adopted_at="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || adopted_at=""
  anchor="$(git rev-parse HEAD 2>/dev/null)" || anchor=""

  local adoption_json
  adoption_json="$(jq -n \
    --arg at "$adopted_at" \
    --arg anchor "$anchor" \
    --arg scenario "$scenario" \
    --argjson landed "$landed_phase" \
    --argjson kindA "$kind_a" \
    --argjson kindB "$kind_b" \
    --argjson kindC "$kind_c" \
    --argjson blockers "$blockers" \
    --arg sha "$scanner_sha" \
    '{schemaVersion: 1, adopted: true, adoptedAt: $at, adoptedAtCommit: $anchor,
      scenario: $scenario, landedPhase: $landed,
      certification: {kindA: $kindA, kindB: $kindB, kindC: $kindC},
      blockersAccepted: $blockers, scannerReportSha256: $sha}')" || return 1

  # Merge — atomic rename, the soif_currency_stamp filter's own form.
  jq --argjson adoption "$adoption_json" '.adoption = $adoption' \
    "$manifest" > "$manifest.tmp" && mv "$manifest.tmp" "$manifest"   # BF-ADOPT-STAMP-MERGE
}

# ── 3. THE BOUND ────────────────────────────────────────────────────────────
# soif_adoption_pre_adoption_commit [manifest] — returns 0 iff the commit about
# to be authored belongs to PRE-ADOPTION history, i.e. sits at or before the
# adoption commit (§5.3's kind (c) scope, in as many words).
#
# THE BOUND IS THE WHOLE DESIGN. An exemption scoped to pre-adoption commits is
# what §5.3 specifies; an UNBOUNDED one is a permanent TDD waiver wearing an
# adoption badge, and §4.5 is explicit that no arm anywhere exempts a commit
# written after adoption day.
#
# ── THE REACHABILITY MODEL, corrected (adversarial review R-WP3-1) ──────────
# The first version of this arm exempted three states, the third being "the
# anchor is not an ancestor of HEAD — a branch cut before adoption, therefore
# pre-adoption history". THAT WAS REFUTED, and the refutation is the key to
# reading this function correctly:
#
#   A genuinely pre-adoption branch has the PRE-ADOPTION manifest checked out.
#   It carries no `adoption` block, so soif_adoption_adopted fails and this
#   function returns at its first line. The state that arm claimed to serve
#   CANNOT REACH IT.
#
# Which inverts the whole picture. Reaching this code at all requires the
# WORKING TREE to carry the stamp — and a working tree carries the stamp only
# because the adoption already happened. So every reachable "not an ancestor"
# state is POST-adoption with rearranged history: a local `git rebase` or
# filter-branch that rewrote the anchor commit, a SQUASH-MERGED adoption branch
# (a GitHub default — and it exempts every subsequent mainline commit forever),
# an orphan branch carrying the stamped tree, or a cherry-picked adoption
# commit. Six of ten live attacks exempted a post-adoption commit. §4.5 says no
# arm anywhere exempts a commit written after adoption day; that arm did
# nothing else.
#
# The corrected predicate is therefore TWO CONJUNCTS, not three cases:
#
#   EXEMPT iff  anchor == HEAD                       (the adoption window)
#          AND  HEAD's COMMITTED manifest is not yet adopted
#
# Conjunct 1 alone kills every rearranged history above, because in all of them
# HEAD is not the recorded anchor. Conjunct 2 is what kills the two attacks
# that manufacture `anchor == HEAD` after the fact — a second stamp moving the
# anchor to the current tip, and a working-copy edit doing the same by hand.
# Once the adoption commit has landed, HEAD's committed manifest is adopted by
# definition, so conjunct 2 is exactly "the adoption has not landed yet".
#
# What remains exempt is one state and one only: the ADOPTION WINDOW — the
# stamp is written, the adoption commit has not been made. That is the set
# §5.3 names ("commits at or before the adoption commit"), and the arm claims
# nothing wider. In particular an adoptee's existing history is never re-judged,
# because the gate only ever judges PROSPECTIVE commits.
#
# Every unknown fails CLOSED (NOT exempt): not adopted, no anchor recorded, an
# anchor this repository does not contain (a bogus 40-hex value, or a shallow
# clone that lacks the object), an unborn HEAD, or no git at all.
#
# KNOWN RESIDUALS — MEASURED, not reasoned about, and recorded rather than
# papered over. Three tamper states were executed against this predicate:
#   • anchor tampered to HEAD, manifest COMMITTED (the shipped configuration):
#     BLOCKED. This is the case R-WP3-3 raised, and conjunct 2 closes it; T7h
#     pins it.
#   • `git reset --mixed` back to the anchor: EXEMPT — and correctly so. The
#     operator has un-committed the adoption commit, which puts the project
#     genuinely back in the adoption window. It is the window's definition, not
#     a way around it, and it costs a deliberate destructive command.
#   • anchor tampered to HEAD on a project whose manifest was NEVER COMMITTED:
#     EXEMPT. A real residue: with no committed copy there is no witness for
#     conjunct 2 to consult. It needs an untracked `.claude/manifest.json`,
#     which is NOT the shipped configuration (the generated .gitignore ignores
#     only the two `.claude/*.txt` sidecars), plus a hand-edit of the record.
#     That is §5.4's honest limit 2 exactly: you can route around the block,
#     not around the record — the edit stays in the file for anyone to read.
soif_adoption_pre_adoption_commit() {
  local manifest="${1:-.claude/manifest.json}"
  soif_adoption_adopted "$manifest" || return 1

  local anchor head
  anchor="$(soif_adoption_read "$manifest" '.adoption.adoptedAtCommit // ""')" || anchor=""
  [ -n "$anchor" ] || return 1
  anchor="$(git rev-parse --verify --quiet "${anchor}^{commit}" 2>/dev/null)" || anchor=""
  [ -n "$anchor" ] || return 1
  head="$(git rev-parse --verify --quiet 'HEAD^{commit}' 2>/dev/null)" || head=""
  [ -n "$head" ] || return 1

  if [ "$anchor" != "$head" ] || _soif_adoption_head_copy_adopted "$manifest"; then   # BF-ADOPT-BOUND
    return 1
  fi
  return 0
}

# ── 4. THE REGENERATE-PATH DETECTOR ─────────────────────────────────────────
# soif_adoption_integrity_lost [manifest] — returns 0 iff this project's
# COMMITTED manifest records an adoption but the WORKING COPY no longer does.
#
# That is the signature of the regenerate path (§12-12): the manifest is lost
# to some cause, the repair path regenerates it wholesale from an upstream key
# set carrying no Solo keys, and the project silently un-adopts. The committed
# copy at HEAD is the witness — it is not rewritten by a working-copy
# regeneration, and it needs no second state file, so the dual-source ban holds.
#
# Every arm fails QUIET (rc 1, no finding) rather than risk a false alarm: no
# jq, no git, a manifest never committed, or a HEAD copy that never claimed
# adoption. The one honest residual is stated here rather than hidden: a stamp
# written but not yet COMMITTED has no witness, so a manifest regenerated
# inside the adoption window is a loss this cannot see. That window is minutes
# long and ends at the adoption commit.
soif_adoption_integrity_lost() {
  local manifest="${1:-.claude/manifest.json}"
  # The committed witness, through the SHARED primitive — the same one the
  # BOUND consults, so there is one implementation of "has the adoption landed"
  # and one thing for a mutation proof to neuter. "Cannot answer" lands here as
  # NO FINDING, which is the quiet direction this consumer wants.
  _soif_adoption_head_copy_adopted "$manifest" || return 1

  # HEAD says adopted. If the working copy still says so, nothing was lost.
  if soif_adoption_adopted "$manifest"; then
    return 1
  fi
  return 0   # BF-ADOPT-LOSS-DETECT
}

# soif_adoption_report_loss [manifest] — the LOUD report. stderr, named cause,
# concrete repair. Printing is all this does; the CALLER owns the verdict (in
# check-phase-gate.sh that means an `issues` increment, because in that script
# the [WARN]/[FAIL] label is cosmetic and the increment is the whole gate).
soif_adoption_report_loss() {
  local manifest="${1:-.claude/manifest.json}"
  {
    echo "[FAIL] Adoption stamp LOST from $manifest."
    echo "       The copy committed at HEAD records this project as ADOPTED; the working"
    echo "       copy does not. The project has silently un-adopted: every gate arm that"
    echo "       reads the adoption flag now reads FALSE, and the certification record of"
    echo "       how this project entered the framework is gone from the live manifest."
    echo "       LIKELY CAUSE: the manifest was missing and a repair path regenerated it"
    echo "       wholesale from the upstream framework's own key set, which carries none"
    echo "       of this framework's keys. That writer is upstream and cannot be stopped"
    echo "       from here — which is why this is reported rather than prevented."
    echo "       REPAIR (re-merges only the adoption block, keeps the regenerated rest):"
    echo "         git show HEAD:$manifest | jq '.adoption' > /tmp/adoption.json && \\"
    echo "         jq --slurpfile a /tmp/adoption.json '.adoption = \$a[0]' $manifest \\"
    echo "           > $manifest.tmp && mv $manifest.tmp $manifest"
  } >&2
}

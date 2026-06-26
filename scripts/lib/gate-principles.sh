# scripts/lib/gate-principles.sh — BL-030 block-message principle lookup.
#
# Every block message printed by the strict-mode framework gate must carry
# both the procedure (what to do to unblock) AND the principle (why the
# rule exists). This library provides the principle text. Keeping it
# co-located with the gate logic avoids drift between docs and behavior.

# shellcheck shell=bash

# principle_for <gate_name>
# Echoes the multi-line "Why this rule exists" paragraph for <gate_name>.
# Returns 0 always (echoes a generic fallback for unknown gates).
principle_for() {
  local gate="${1:-}"
  case "$gate" in
    commit-classifier)
      cat <<'EOF'
  Phase 2 'feat:' commits must be preceded by an open Build Loop with
  the first 5 steps complete (tests written, tests verified failing,
  implemented, security audit, documentation updated). The classifier
  prevents 'feat:' commits that haven't earned the right to claim a
  feature was added — the framework's value is only as strong as the
  discipline of its commit boundary.
EOF
      ;;
    phase-prereq)
      cat <<'EOF'
  Phase 2 (Build Loop, source commits) requires a configured remote so
  every commit has a durable home and the framework's audit trail
  survives a local disk loss. Without a remote, work that looks committed
  exists only in one place — handoff-readiness (the framework's central
  value prop) is structurally impossible. This rule fired because Phase 2
  was claimed but no git remote is configured.
EOF
      ;;
    build-loop)
      cat <<'EOF'
  Source commits in Phase 2 must be preceded by a complete Build Loop:
  tests written, tests verified failing, implementation, security audit,
  documentation updated. Skipping a step writes code without the
  discipline that makes it auditable, testable, and handoff-ready. The
  block fires when one of these steps is missing for the current feature.
EOF
      ;;
    *)
      cat <<'EOF'
  This block fires when a framework gate detects a process violation.
  The gate name above identifies which rule fired; consult the user
  guide (docs/user-guide.md) for the principle behind the specific gate.
EOF
      ;;
  esac
}

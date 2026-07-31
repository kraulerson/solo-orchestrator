#!/usr/bin/env bash
# Solo Orchestrator — first-timer alias for scripts/resume.sh (BL-202).
# "Resume" reads wrong before anything has started; this name does not.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resume.sh" "$@"

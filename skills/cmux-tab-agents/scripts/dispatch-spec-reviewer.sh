#!/usr/bin/env bash
# dispatch-spec-reviewer.sh — spawn a SPEC COMPLIANCE REVIEWER tab-agent.
#
# Verifies that the implementer built what was specified — nothing more,
# nothing less. Forks superpowers:subagent-driven-development's spec reviewer.
# Pass --implementer-sha so the reviewer can scope its read to that commit.

set -euo pipefail
# shellcheck disable=SC2034 # PHASE is consumed by sourced _dispatch_common.sh
PHASE="spec-reviewer"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_dispatch_common.sh
source "$SCRIPT_DIR/_dispatch_common.sh"
dispatch_main "$@"

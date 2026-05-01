#!/usr/bin/env bash
# dispatch-code-reviewer.sh — spawn a CODE QUALITY REVIEWER tab-agent.
#
# Verifies that the implementation is well-built (clean, tested, maintainable).
# Forks superpowers:subagent-driven-development's code quality reviewer.
# Run this only after the spec-reviewer has reported APPROVED.
# Pass --implementer-sha so the reviewer can scope its read to that commit.

set -euo pipefail
PHASE="code-reviewer"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_dispatch_common.sh
source "$SCRIPT_DIR/_dispatch_common.sh"
dispatch_main "$@"

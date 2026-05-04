#!/usr/bin/env bash
# dispatch-implementer.sh — spawn an IMPLEMENTER tab-agent in a cmux tab.
#
# Forks superpowers:subagent-driven-development's implementer subagent into a
# real `claude` process running in its own git worktree. See
# ../prompts/implementer-tab-prompt.md for the seed prompt.
#
# Echoes the new tab's surface_ref on stdout. Status pill `<TICKET>-implementer`
# is set on the planner's workspace.

set -euo pipefail
# shellcheck disable=SC2034 # PHASE is consumed by sourced _dispatch_common.sh
PHASE="implementer"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_dispatch_common.sh
source "$SCRIPT_DIR/_dispatch_common.sh"
dispatch_main "$@"

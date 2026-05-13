#!/usr/bin/env bash
# session_start.sh — SessionStart hook: set the working pill, log the start.
#
# Replaces the boot-sequence steps that lived in every tab-agent prompt. The
# hook receives Claude Code's standard SessionStart payload on stdin; we only
# need `cwd` to find the dispatch.json that the dispatch script wrote.
#
# Failure modes are swallowed: a missing dispatch.json, an absent `cmux`
# binary, or a mangled stdin payload all silently no-op so the agent's session
# is never blocked by lifecycle plumbing.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib_hook_common.sh
source "$SCRIPT_DIR/lib_hook_common.sh"

hook_read_stdin

WT=$(hook_locate_worktree)
[[ -z "$WT" ]] && exit 0

TICKET=$(hook_dispatch_field "$WT" ticket)
PHASE=$(hook_dispatch_field "$WT" phase)
PLANNER_WS=$(hook_dispatch_field "$WT" planner_workspace)

# Without a ticket+phase pair there is no pill to set; nothing useful to do.
[[ -z "$TICKET" || -z "$PHASE" ]] && exit 0

PILL="${TICKET}-${PHASE}"

# Mirror the prompt's old boot sequence: pill on the agent's own workspace
# and on the planner's, plus a log entry. Both colors / icons match the
# pre-hook conventions in status-conventions.md.
hook_cmux set-status "$PILL" "working" --icon hammer --color "#ff9500"
if [[ -n "$PLANNER_WS" ]]; then
  hook_cmux set-status "$PILL" "working" --icon hammer --color "#ff9500" \
    --workspace "$PLANNER_WS"
fi
hook_cmux log "starting ${PHASE} for ${TICKET}" --level info

# ISSUE-178: launch periodic agent health check in background. Best-effort —
# any failure is swallowed so it never blocks the agent session. The PID is
# recorded so the Stop hook can reap the loop on shutdown.
HEALTH_SCRIPT="$SCRIPT_DIR/../scripts/health-check.sh"
HEALTH_INTERVAL="${CMUX_HEALTH_INTERVAL:-30}"
if [[ -x "$HEALTH_SCRIPT" ]]; then
  mkdir -p "$WT/.cmux-state" 2>/dev/null || true
  HEALTH_PID_FILE="$WT/.cmux-state/health.pid"
  # Avoid duplicate loops: if a prior PID is still alive, leave it.
  if [[ -f "$HEALTH_PID_FILE" ]] && kill -0 "$(cat "$HEALTH_PID_FILE" 2>/dev/null)" 2>/dev/null; then
    : # already running
  else
    ( cd "$WT" && nohup bash "$HEALTH_SCRIPT" --interval "$HEALTH_INTERVAL" --no-restart \
        >> "$WT/.cmux-state/health.log" 2>&1 &
      echo $! > "$HEALTH_PID_FILE"
    ) >/dev/null 2>&1 || true
  fi
fi

exit 0

#!/usr/bin/env bash
# stop.sh — Stop hook: flip the terminal-state pill, notify, and (only as a
# safety net) write a BLOCKED stub if the agent exited without writing its
# canonical result file.
#
# CRITICAL: this hook is NOT the author of the result file's body or schema.
# The agent prompt is. The hook only writes a minimal stub when the result
# file is absent (process killed, OOM, etc.) so the planner's
# poll-result.sh sees `status: BLOCKED` instead of timing out forever.

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

# Without a ticket+phase we cannot form pill names or result paths; bail.
[[ -z "$TICKET" || -z "$PHASE" ]] && exit 0

# poll-result.sh expects `.cmux-<phase>-result.md` but the implementer also
# writes a `.cmux-task-result.md` task-lead roll-up; the per-phase file is
# what the next phase consumes, so that is what we guard.
PHASE_FILE="$WT/.cmux-${PHASE}-result.md"

# Safety net: if the agent crashed before writing its result file, drop a
# minimal BLOCKED stub so the planner's poll exits cleanly. We never
# overwrite an agent-authored file; the schema is the prompt's responsibility.
if [[ ! -f "$PHASE_FILE" ]]; then
  cat > "$PHASE_FILE" <<EOF
---
ticket: ${TICKET}
phase: ${PHASE}
status: BLOCKED
authored_by: stop_hook_safety_net
---
## Summary

The agent process exited without writing this result file. The Stop hook
wrote this stub so the planner's poll terminates instead of hanging.

## Likely causes

- The agent was killed (SIGKILL, OOM, terminal closed).
- The agent crashed before reaching its terminal-state report step.
- A bug in the agent's prompt skipped the result-file write.

## Next steps

- Inspect \`${WT}/.cmux-events.jsonl\` for the last tool the agent ran.
- Re-dispatch the phase if the cause was transient.
EOF
fi

# Decide the terminal pill state. If the result file (agent-authored or stub)
# has a parseable `status:` field, mirror it to the pill; otherwise BLOCKED.
STATUS=""
if [[ -f "$PHASE_FILE" ]]; then
  STATUS=$(awk -F': *' '/^status:/ {print $2; exit}' "$PHASE_FILE" 2>/dev/null | tr -d '[:space:]' || true)
fi
[[ -z "$STATUS" ]] && STATUS="BLOCKED"

case "$STATUS" in
  DONE|APPROVED)            ICON="checkmark.seal"; COLOR="#34c759" ;;
  DONE_WITH_CONCERNS)       ICON="exclamationmark.triangle"; COLOR="#ffcc00" ;;
  ISSUES_FOUND|NEEDS_CONTEXT) ICON="exclamationmark.triangle"; COLOR="#ff9500" ;;
  BLOCKED|*)                ICON="xmark.octagon"; COLOR="#ff3b30" ;;
esac

PILL="${TICKET}-${PHASE}"
hook_cmux set-status "$PILL" "$STATUS" --icon "$ICON" --color "$COLOR"
if [[ -n "$PLANNER_WS" ]]; then
  hook_cmux set-status "$PILL" "$STATUS" --icon "$ICON" --color "$COLOR" \
    --workspace "$PLANNER_WS"
fi
hook_cmux notify "${PILL}: ${STATUS}"

exit 0

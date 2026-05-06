#!/usr/bin/env bash
# post_tool_use.sh — PostToolUse hook: append a single JSONL event line.
#
# Foundation for a future events-stream tab. We deliberately keep the line
# small (no tool inputs/outputs) to avoid leaking secrets and to keep the
# file cheap to tail. No consumer is required for this hook to be useful —
# the file is purely additive.
#
# The hook is best-effort: any failure (missing jq, missing dispatch.json,
# unwritable disk) is swallowed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib_hook_common.sh
source "$SCRIPT_DIR/lib_hook_common.sh"

hook_read_stdin

WT=$(hook_locate_worktree)
[[ -z "$WT" ]] && exit 0

SESSION_ID=$(hook_field session_id)
TOOL_NAME=$(hook_field tool_name)

# A tool-name-less payload is malformed; nothing to record.
[[ -z "$TOOL_NAME" ]] && exit 0

# tool_response is a structured object; we only care whether it indicated an
# error. `is_error: true` is the documented failure marker.
OK=true
if command -v jq >/dev/null 2>&1 && [[ -n "${HOOK_STDIN_JSON:-}" ]]; then
  if jq -e '.tool_response.is_error == true' <<<"$HOOK_STDIN_JSON" >/dev/null 2>&1; then
    OK=false
  fi
fi

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EVENTS="$WT/.cmux-events.jsonl"

# Compose the line via jq when available so embedded quotes/newlines are
# escaped correctly; fall back to a hand-built JSON if jq is missing.
if command -v jq >/dev/null 2>&1; then
  LINE=$(jq -cn \
    --arg ts "$TS" --arg sid "$SESSION_ID" --arg tool "$TOOL_NAME" \
    --argjson ok "$OK" \
    '{ts:$ts, session_id:$sid, tool_name:$tool, ok:$ok}')
else
  # Fallback: tool_name is unlikely to contain quotes; if it does we accept
  # producing a slightly malformed line rather than blocking the agent.
  LINE="{\"ts\":\"$TS\",\"session_id\":\"$SESSION_ID\",\"tool_name\":\"$TOOL_NAME\",\"ok\":$OK}"
fi

printf '%s\n' "$LINE" >> "$EVENTS" 2>/dev/null || true
exit 0

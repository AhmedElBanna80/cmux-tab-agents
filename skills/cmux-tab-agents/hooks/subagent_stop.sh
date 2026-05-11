#!/usr/bin/env bash
# subagent_stop.sh — SubagentStop hook: append a FINISHED line to the per-agent log.
#
# Reads agent_id and agent_transcript_path from the hook payload. Appends a
# SubagentStop event line (with last_assistant_message if the transcript is
# readable) to ~/.cmux-tab-agents/agents/<agent_id>.jsonl.
#
# Best-effort: failures are swallowed so the agent session is never blocked.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib_hook_common.sh
source "$SCRIPT_DIR/lib_hook_common.sh"

hook_read_stdin

AGENT_ID=$(hook_field agent_id)
[[ -z "$AGENT_ID" ]] && exit 0

AGENTS_DIR="${CMUX_AGENT_STATE_DIR:-$HOME/.cmux-tab-agents/agents}"
AGENT_LOG="$AGENTS_DIR/${AGENT_ID}.jsonl"

TRANSCRIPT_PATH=$(hook_field agent_transcript_path)
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SESSION_ID=$(hook_field session_id)

# Extract last assistant message from the transcript (best-effort, first 500 chars).
LAST_MSG=""
if [[ -n "$TRANSCRIPT_PATH" && -f "$TRANSCRIPT_PATH" ]] && command -v jq >/dev/null 2>&1; then
  LAST_MSG=$(jq -r '
    [.[] | select(.role == "assistant")] | last |
    .content |
    if type == "array" then map(select(.type == "text").text) | join("") else . end
  ' "$TRANSCRIPT_PATH" 2>/dev/null | head -c 500 || true)
fi

if command -v jq >/dev/null 2>&1; then
  LINE=$(jq -cn \
    --arg ts "$TS" --arg sid "$SESSION_ID" --arg aid "$AGENT_ID" \
    --arg event "SubagentStop" --arg last_msg "${LAST_MSG:-}" \
    '{ts:$ts, session_id:$sid, agent_id:$aid, event:$event, last_assistant_message:$last_msg}')
else
  LINE="{\"ts\":\"$TS\",\"agent_id\":\"$AGENT_ID\",\"event\":\"SubagentStop\"}"
fi

mkdir -p "$AGENTS_DIR" 2>/dev/null || true
printf '%s\n' "$LINE" >> "$AGENT_LOG" 2>/dev/null || true
exit 0

#!/usr/bin/env bash
# post_tool_use.sh — PostToolUse hook: append a single JSONL event line.
#
# Two independent paths (both best-effort):
#   1. Tab-agent path: write to <worktree>/.cmux-events.jsonl when running
#      inside a cmux-tab-agents worktree (dispatch.json present).
#   2. Task() subagent path: write to ~/.cmux-tab-agents/agents/<agent_id>.jsonl
#      when agent_id is present in the hook payload (planner-level visibility).
#
# The hook is best-effort: any failure (missing jq, missing dispatch.json,
# unwritable disk) is swallowed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib_hook_common.sh
source "$SCRIPT_DIR/lib_hook_common.sh"

hook_read_stdin

TOOL_NAME=$(hook_field tool_name)

# A tool-name-less payload is malformed; nothing useful to record in either path.
[[ -z "$TOOL_NAME" ]] && exit 0

SESSION_ID=$(hook_field session_id)

# tool_response is a structured object; we only care whether it indicated an
# error. `is_error: true` is the documented failure marker.
OK=true
if command -v jq >/dev/null 2>&1 && [[ -n "${HOOK_STDIN_JSON:-}" ]]; then
  if jq -e '.tool_response.is_error == true' <<<"$HOOK_STDIN_JSON" >/dev/null 2>&1; then
    OK=false
  fi
fi

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ── Path 1: tab-agent worktree events ────────────────────────────────────────
WT=$(hook_locate_worktree)
if [[ -n "$WT" ]]; then
  EVENTS="$WT/.cmux-events.jsonl"
  # Compose the line via jq when available so embedded quotes/newlines are
  # escaped correctly; fall back to a hand-built JSON if jq is missing.
  if command -v jq >/dev/null 2>&1; then
    LINE=$(jq -cn \
      --arg ts "$TS" --arg sid "$SESSION_ID" --arg tool "$TOOL_NAME" \
      --argjson ok "$OK" \
      '{ts:$ts, session_id:$sid, tool_name:$tool, ok:$ok}')
  else
    LINE="{\"ts\":\"$TS\",\"session_id\":\"$SESSION_ID\",\"tool_name\":\"$TOOL_NAME\",\"ok\":$OK}"
  fi
  printf '%s\n' "$LINE" >> "$EVENTS" 2>/dev/null || true
fi

# ── Path 2: Task() per-agent event log ───────────────────────────────────────
AGENT_ID=$(hook_field agent_id)
if [[ -n "$AGENT_ID" ]]; then
  AGENTS_DIR="${CMUX_AGENT_STATE_DIR:-$HOME/.cmux-tab-agents/agents}"
  AGENT_LOG="$AGENTS_DIR/${AGENT_ID}.jsonl"
  if command -v jq >/dev/null 2>&1; then
    AGENT_LINE=$(jq -cn \
      --arg ts "$TS" --arg sid "$SESSION_ID" --arg aid "$AGENT_ID" \
      --arg event "PostToolUse" --arg tool "$TOOL_NAME" \
      --argjson ok "$OK" \
      '{ts:$ts, session_id:$sid, agent_id:$aid, event:$event, tool_name:$tool, ok:$ok}')
  else
    AGENT_LINE="{\"ts\":\"$TS\",\"agent_id\":\"$AGENT_ID\",\"event\":\"PostToolUse\",\"tool_name\":\"$TOOL_NAME\",\"ok\":$OK}"
  fi
  mkdir -p "$AGENTS_DIR" 2>/dev/null || true
  printf '%s\n' "$AGENT_LINE" >> "$AGENT_LOG" 2>/dev/null || true
fi

exit 0

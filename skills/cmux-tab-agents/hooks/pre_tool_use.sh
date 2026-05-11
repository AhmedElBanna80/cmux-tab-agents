#!/usr/bin/env bash
# pre_tool_use.sh — PreToolUse hook: spawn a cmux tab for new Task() subagents.
#
# Routes by agent_id. When agent_id appears in the hook payload for the first
# time, a new cmux surface is spawned in the agents pane and the mapping is
# persisted. Every call appends a JSONL event line to the per-agent log file.
#
# State dir: ${CMUX_AGENT_STATE_DIR:-~/.cmux-tab-agents/agents}
#   agent_tabs.json   — agent_id → surface_ref map
#   <agent_id>.jsonl  — per-agent event log (consumed by agent-tab-renderer.sh)
#
# Best-effort: any failure (missing jq, missing cmux, unwritable disk) is
# swallowed so the agent session is never blocked by this hook.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib_hook_common.sh
source "$SCRIPT_DIR/lib_hook_common.sh"

hook_read_stdin

AGENT_ID=$(hook_field agent_id)
[[ -z "$AGENT_ID" ]] && exit 0

AGENTS_DIR="${CMUX_AGENT_STATE_DIR:-$HOME/.cmux-tab-agents/agents}"
mkdir -p "$AGENTS_DIR" 2>/dev/null || true

AGENT_TABS_FILE="$AGENTS_DIR/agent_tabs.json"
AGENT_LOG="$AGENTS_DIR/${AGENT_ID}.jsonl"

# Check if this agent_id is already mapped to a surface.
SURFACE_REF=""
if [[ -f "$AGENT_TABS_FILE" ]] && command -v jq >/dev/null 2>&1; then
  SURFACE_REF=$(jq -r --arg id "$AGENT_ID" '.[$id] // empty' "$AGENT_TABS_FILE" 2>/dev/null || true)
fi

if [[ -z "$SURFACE_REF" ]]; then
  # New agent: resolve the agents pane then spawn a new surface inside it.
  if command -v cmux >/dev/null 2>&1; then
    AGENTS_PANE="${CMUX_AGENTS_PANE:-}"
    if [[ -z "$AGENTS_PANE" ]]; then
      SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../scripts" && pwd)"
      if [[ -x "$SCRIPTS_DIR/resolve-agents-pane.sh" ]]; then
        AGENTS_PANE=$("$SCRIPTS_DIR/resolve-agents-pane.sh" \
          --caller-surface "${CMUX_SURFACE_ID:-}" \
          --caller-pane "${CMUX_PANE_ID:-}" \
          --workspace "${CMUX_WORKSPACE_ID:-}" 2>/dev/null || true)
      fi
    fi
    if [[ -n "$AGENTS_PANE" ]]; then
      SURFACE_REF=$(cmux new-surface --pane "$AGENTS_PANE" 2>/dev/null || true)
    else
      SURFACE_REF=$(cmux new-surface 2>/dev/null || true)
    fi
  fi

  # Persist agent_id → surface_ref (empty string is valid; records we saw the agent).
  if command -v jq >/dev/null 2>&1; then
    EXISTING="{}"
    [[ -f "$AGENT_TABS_FILE" ]] && EXISTING=$(jq '.' "$AGENT_TABS_FILE" 2>/dev/null || echo "{}")
    jq --arg id "$AGENT_ID" --arg ref "${SURFACE_REF:-}" \
       '. + {($id): $ref}' <<<"$EXISTING" > "$AGENT_TABS_FILE.tmp" 2>/dev/null \
      && mv "$AGENT_TABS_FILE.tmp" "$AGENT_TABS_FILE" 2>/dev/null || true
  fi
fi

# Append PreToolUse event line to the per-agent log.
TOOL_NAME=$(hook_field tool_name)
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SESSION_ID=$(hook_field session_id)

if command -v jq >/dev/null 2>&1; then
  LINE=$(jq -cn \
    --arg ts "$TS" --arg sid "$SESSION_ID" --arg aid "$AGENT_ID" \
    --arg event "PreToolUse" --arg tool "${TOOL_NAME:-}" \
    '{ts:$ts, session_id:$sid, agent_id:$aid, event:$event, tool_name:$tool}')
else
  LINE="{\"ts\":\"$TS\",\"agent_id\":\"$AGENT_ID\",\"event\":\"PreToolUse\",\"tool_name\":\"${TOOL_NAME:-}\"}"
fi

printf '%s\n' "$LINE" >> "$AGENT_LOG" 2>/dev/null || true
exit 0

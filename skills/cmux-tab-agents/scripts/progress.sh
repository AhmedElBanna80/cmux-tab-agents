#!/usr/bin/env bash
# progress.sh — append a structured JSONL progress event to .cmux-progress.jsonl
#
# Usage:
#   progress.sh [--role <role>] started <step> <name>
#   progress.sh [--role <role>] done <step>
#   progress.sh [--role <role>] terminal <verdict>
#
# --role: implementer (default) | spec-reviewer | code-reviewer
#
# The file is created in the current working directory (the worktree root).
# Best-effort: all errors are swallowed so this never blocks the agent.

AGENT_ROLE="implementer"
SRC="implementer"

# Parse optional --role flag (may appear before positional args)
while [[ "${1:-}" == "--role" ]]; do
  AGENT_ROLE="${2:-implementer}"
  shift 2
done

# Map role to short src value
case "$AGENT_ROLE" in
  spec-reviewer)  SRC="spec" ;;
  code-reviewer)  SRC="code" ;;
  *)              SRC="implementer" ;;
esac

KIND="${1:-}"
STEP="${2:-}"
NAME="${3:-step-$STEP}"

[[ -z "$KIND" || -z "$STEP" ]] && exit 0

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || TS=""
SID="${CLAUDE_SESSION_ID:-${SESSION_ID:-}}"
PROGRESS_FILE=".cmux-progress.jsonl"

if command -v jq >/dev/null 2>&1; then
  LINE=$(jq -cn \
    --argjson v 1 \
    --arg ts "$TS" \
    --arg src "$SRC" \
    --arg sid "$SID" \
    --arg kind "$KIND" \
    --arg name "$NAME" \
    --arg agent_role "$AGENT_ROLE" \
    --arg step "$STEP" \
    '{v:$v, ts:$ts, src:$src, sid:$sid, kind:$kind, name:$name, agent_role:$agent_role, payload:{step:$step, agent_role:$agent_role}}' 2>/dev/null) || LINE=""
else
  LINE="{\"v\":1,\"ts\":\"$TS\",\"src\":\"$SRC\",\"sid\":\"$SID\",\"kind\":\"$KIND\",\"name\":\"$NAME\",\"agent_role\":\"$AGENT_ROLE\",\"payload\":{\"step\":\"$STEP\",\"agent_role\":\"$AGENT_ROLE\"}}"
fi

[[ -z "$LINE" ]] && exit 0
printf '%s\n' "$LINE" >> "$PROGRESS_FILE" 2>/dev/null || true
exit 0

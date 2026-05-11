#!/usr/bin/env bash
# progress.sh — append a structured JSONL progress event to .cmux-progress.jsonl
#
# Usage:
#   progress.sh started <step> <name>
#   progress.sh done <step>
#
# The file is created in the current working directory (the worktree root).
# Best-effort: all errors are swallowed so this never blocks the agent.

KIND="${1:-}"
STEP="${2:-}"
NAME="${3:-step-$STEP}"

[[ -z "$KIND" || -z "$STEP" ]] && exit 0

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || TS=""
SID="${CLAUDE_SESSION_ID:-${SESSION_ID:-}}"
SRC="implementer"
PROGRESS_FILE=".cmux-progress.jsonl"

if command -v jq >/dev/null 2>&1; then
  LINE=$(jq -cn \
    --argjson v 1 \
    --arg ts "$TS" \
    --arg src "$SRC" \
    --arg sid "$SID" \
    --arg kind "$KIND" \
    --arg name "$NAME" \
    --argjson payload "{\"step\":$STEP}" \
    '{v:$v, ts:$ts, src:$src, sid:$sid, kind:$kind, name:$name, payload:$payload}' 2>/dev/null) || LINE=""
else
  LINE="{\"v\":1,\"ts\":\"$TS\",\"src\":\"$SRC\",\"sid\":\"$SID\",\"kind\":\"$KIND\",\"name\":\"$NAME\",\"payload\":{\"step\":$STEP}}"
fi

[[ -z "$LINE" ]] && exit 0
printf '%s\n' "$LINE" >> "$PROGRESS_FILE" 2>/dev/null || true
exit 0

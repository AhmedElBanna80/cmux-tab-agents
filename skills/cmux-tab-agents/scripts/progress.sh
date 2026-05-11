#!/usr/bin/env bash
# progress.sh — append a structured JSONL progress event to .cmux-progress.jsonl
#
# Usage:
#   progress.sh [--role <role>] [--target <role[,role]>] \
#               [--verdict <APPROVED|ISSUES_FOUND|BLOCKED|...>] \
#               [--feedback <text>] [--issue-hash <hash>] \
#               <kind> <step> [<name>]
#
# --role:       implementer (default) | spec-reviewer | code-reviewer
# --target:     who receives this event — enables v2 schema for agent-to-agent coordination
# --verdict:    reviewer verdict; when provided with no positional kind, kind defaults to "verdict"
# --feedback:   short message accompanying a verdict or feedback event
# --issue-hash: stable hash of the issue body for circuit-breaker dedup
#
# The file is created in the current working directory (the worktree root).
# Best-effort: all errors are swallowed so this never blocks the agent.

AGENT_ROLE="implementer"
SRC="implementer"
TARGET=""
VERDICT=""
FEEDBACK=""
ISSUE_HASH=""

# Parse leading optional flags (order-independent).
# Use single shifts so malformed input (e.g. trailing "--target" with no value)
# never spins the loop.
while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --role)       AGENT_ROLE="${2:-implementer}"; shift; [[ $# -gt 0 ]] && shift ;;
    --target)     TARGET="${2:-}";                shift; [[ $# -gt 0 ]] && shift ;;
    --verdict)    VERDICT="${2:-}";               shift; [[ $# -gt 0 ]] && shift ;;
    --feedback)   FEEDBACK="${2:-}";              shift; [[ $# -gt 0 ]] && shift ;;
    --issue-hash) ISSUE_HASH="${2:-}";            shift; [[ $# -gt 0 ]] && shift ;;
    --) shift; break ;;
    *) break ;;
  esac
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

# If a verdict is set but the positional kind/step pair is incomplete, fall back to kind=verdict
if [[ -n "$VERDICT" && -z "$KIND" ]]; then
  KIND="verdict"
fi

[[ -z "$KIND" || -z "$STEP" ]] && exit 0

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || TS=""
SID="${CLAUDE_SESSION_ID:-${SESSION_ID:-}}"
PROGRESS_FILE=".cmux-progress.jsonl"

# Schema version: v2 if any agent-coordination field set, else v1
SCHEMA_V=1
if [[ -n "$TARGET" || -n "$VERDICT" || -n "$FEEDBACK" || -n "$ISSUE_HASH" ]]; then
  SCHEMA_V=2
fi

if command -v jq >/dev/null 2>&1; then
  if [[ "$SCHEMA_V" -eq 2 ]]; then
    LINE=$(jq -cn \
      --argjson v 2 \
      --arg ts "$TS" \
      --arg src "$SRC" \
      --arg sid "$SID" \
      --arg kind "$KIND" \
      --arg name "$NAME" \
      --arg agent_role "$AGENT_ROLE" \
      --arg step "$STEP" \
      --arg target "$TARGET" \
      --arg verdict "$VERDICT" \
      --arg feedback "$FEEDBACK" \
      --arg issue_hash "$ISSUE_HASH" \
      '{v:$v, ts:$ts, src:$src, sid:$sid, kind:$kind, name:$name, agent_role:$agent_role, target:$target}
       + (if $verdict    != "" then {verdict:$verdict}       else {} end)
       + (if $feedback   != "" then {feedback:$feedback}     else {} end)
       + (if $issue_hash != "" then {issue_hash:$issue_hash} else {} end)
       + {payload:{step:$step, agent_role:$agent_role, target:$target, verdict:$verdict, feedback:$feedback, issue_hash:$issue_hash}}' 2>/dev/null) || LINE=""
  else
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
  fi
else
  if [[ "$SCHEMA_V" -eq 2 ]]; then
    LINE="{\"v\":2,\"ts\":\"$TS\",\"src\":\"$SRC\",\"sid\":\"$SID\",\"kind\":\"$KIND\",\"name\":\"$NAME\",\"agent_role\":\"$AGENT_ROLE\",\"target\":\"$TARGET\",\"verdict\":\"$VERDICT\",\"feedback\":\"$FEEDBACK\",\"issue_hash\":\"$ISSUE_HASH\",\"payload\":{\"step\":\"$STEP\",\"agent_role\":\"$AGENT_ROLE\"}}"
  else
    LINE="{\"v\":1,\"ts\":\"$TS\",\"src\":\"$SRC\",\"sid\":\"$SID\",\"kind\":\"$KIND\",\"name\":\"$NAME\",\"agent_role\":\"$AGENT_ROLE\",\"payload\":{\"step\":\"$STEP\",\"agent_role\":\"$AGENT_ROLE\"}}"
  fi
fi

[[ -z "$LINE" ]] && exit 0
printf '%s\n' "$LINE" >> "$PROGRESS_FILE" 2>/dev/null || true
exit 0

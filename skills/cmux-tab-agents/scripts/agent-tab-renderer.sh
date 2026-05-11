#!/usr/bin/env bash
# agent-tab-renderer.sh — pretty-print a per-agent Task() JSONL event log.
#
# Usage: agent-tab-renderer.sh <jsonl-file>
#
# Runs tail -f on the file and pipes each line through jq for human-readable
# formatting. Intended to run inside a cmux tab spawned by pre_tool_use.sh.
# Example output:
#   [12:01:03] PreToolUse   Read
#   [12:01:03] PostToolUse  Read
#   [12:01:45] SubagentStop agent-abc
#     Last: "Implemented validation, 12 tests pass."

set -uo pipefail

usage() {
  echo "Usage: agent-tab-renderer.sh <jsonl-file>" >&2
  exit 1
}

[[ $# -eq 1 ]] || usage
FILE="$1"

touch "$FILE" 2>/dev/null || true

tail -f "$FILE" | jq -r '
  (.ts | split("T") | .[1] | split("Z") | .[0]) as $time |
  .event as $ev |
  (.tool_name // .agent_id // "") as $detail |
  if $ev == "SubagentStop" then
    "[" + $time + "] " + $ev + " " + .agent_id +
    "\n  Last: " + (.last_assistant_message // "")
  else
    "[" + $time + "] " + ($ev | . + (20 - length) * " ") + $detail
  end
'

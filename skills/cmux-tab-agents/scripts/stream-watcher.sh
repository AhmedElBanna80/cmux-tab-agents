#!/usr/bin/env bash
# stream-watcher.sh — monitor .cmux-progress.jsonl for agent coordination events
#
# Agents invoke this to watch the progress stream and react to events targeted at them.
# Supports v2 events with "target" field for peer-to-peer agent coordination.
#
# Usage:
#   source stream-watcher.sh
#   watch_stream <role> <handler_func> [--timeout SECONDS]
#
# <role>:         implementer | spec-reviewer | code-reviewer
# <handler_func>: bash function to invoke on matching events
# --timeout:      exit after N seconds (optional)
#
# Handler signature: handler_func <event_json>
#   The handler receives the full event JSON as a single argument.
#   It is responsible for parsing the event (use jq) and taking action.
#
# Example in implementer-tab-prompt.md:
#   source ~/.claude/skills/cmux-tab-agents/scripts/stream-watcher.sh
#
#   handle_implementer_event() {
#     local event="$1"
#     local verdict=$(echo "$event" | jq -r '.verdict // empty')
#     case "$verdict" in
#       APPROVED) log "Spec approved, moving to code review" ;;
#       ISSUES_FOUND) log "Issues found: $(echo "$event" | jq -r '.feedback')" ;;
#     esac
#   }
#
#   watch_stream implementer handle_implementer_event &

set -o pipefail

# Stream watcher configuration
STREAM_FILE=".cmux-progress.jsonl"
STREAM_WATCHER_PID=""
STREAM_WATCHER_RUNNING=0

# Start watching the stream
watch_stream() {
  local role="$1"
  local handler="$2"
  local timeout=""

  [[ -z "$role" || -z "$handler" ]] && { echo "watch_stream: role and handler required" >&2; return 1; }

  # Parse optional --timeout flag
  shift 2
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --timeout) timeout="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  # Verify handler function exists
  declare -f "$handler" >/dev/null || { echo "watch_stream: handler function '$handler' not defined" >&2; return 1; }

  # Start the watcher in background
  _stream_watcher_loop "$role" "$handler" "$timeout" &
  STREAM_WATCHER_PID=$!
  STREAM_WATCHER_RUNNING=1
}

# Main watcher loop
_stream_watcher_loop() {
  local role="$1"
  local handler="$2"
  local timeout="$3"
  local start_time
  start_time=$(date +%s)
  local last_pos=0

  # If timeout is set, ensure we have a way to check elapsed time
  if [[ -n "$timeout" ]]; then
    trap "exit 0" TERM INT
  fi

  while true; do
    # Check timeout
    if [[ -n "$timeout" ]]; then
      local elapsed=$(($(date +%s) - start_time))
      if [[ $elapsed -ge $timeout ]]; then
        break
      fi
    fi

    # If file doesn't exist yet, wait a bit and continue
    if [[ ! -f "$STREAM_FILE" ]]; then
      sleep 0.5
      continue
    fi

    # Read new lines from the file since last read
    # Use tail to get new lines added since last position
    if [[ $last_pos -eq 0 ]]; then
      # First read: start from beginning but skip to recent events
      # (helps with long-running streams)
      local line_count
      line_count=$(wc -l < "$STREAM_FILE" 2>/dev/null || echo 0)
      if [[ $line_count -gt 100 ]]; then
        last_pos=$((line_count - 10))
      fi
    fi

    # Read lines and process new ones
    local current_line=0
    while IFS= read -r line; do
      current_line=$((current_line + 1))

      # Skip until we reach last known position
      if [[ $current_line -le $last_pos ]]; then
        continue
      fi

      # Empty lines shouldn't happen in JSONL, but skip them
      [[ -z "$line" ]] && continue

      # Try to parse as JSON and check if it's for us
      if _should_handle_event "$line" "$role"; then
        # Call the handler with the full event JSON
        $handler "$line" 2>&1 || true
      fi
    done < "$STREAM_FILE"

    # Update last position
    last_pos=$(wc -l < "$STREAM_FILE" 2>/dev/null || echo 0)

    # Sleep briefly before next poll
    sleep 0.2
  done
}

# Determine if an event should be handled by this role
_should_handle_event() {
  local event="$1"
  local role="$2"

  # Try to extract target field from JSON
  # Events with no target are broadcasts (v1 compat) - agents can ignore them
  # Events with target matching this role should be handled (v2)

  if command -v jq >/dev/null 2>&1; then
    local target
    target=$(echo "$event" | jq -r '.target // empty' 2>/dev/null)

    # If no target, it's a v1 broadcast event - agents can listen but are not required to
    if [[ -z "$target" ]]; then
      return 1  # Only handle targeted events
    fi

    # Check if target matches this role (can be comma-separated)
    if [[ "$target" =~ $role ]]; then
      return 0
    fi
  else
    # Fallback: grep for target
    if echo "$event" | grep -q "\"target\""; then
      if echo "$event" | grep -q "\"$role\""; then
        return 0
      fi
    fi
  fi

  return 1
}

# Stop watching the stream
stop_watching_stream() {
  if [[ -n "$STREAM_WATCHER_PID" && $STREAM_WATCHER_RUNNING -eq 1 ]]; then
    kill "$STREAM_WATCHER_PID" 2>/dev/null || true
    wait "$STREAM_WATCHER_PID" 2>/dev/null || true
    STREAM_WATCHER_PID=""
    STREAM_WATCHER_RUNNING=0
  fi
}

# Trap to clean up watcher on script exit
trap stop_watching_stream EXIT INT TERM

# Helper: read a specific event from stream by index or query
# Usage: get_latest_event <role>
#   Returns the latest event where target includes <role> (or latest event if no target filter)
get_latest_event() {
  local role="${1:-}"

  if command -v jq >/dev/null 2>&1; then
    if [[ -z "$role" ]]; then
      # Get latest event overall
      tail -1 "$STREAM_FILE" 2>/dev/null
    else
      # Get latest event targeting this role
      tac "$STREAM_FILE" 2>/dev/null | jq "select(.target | contains(\"$role\"))" 2>/dev/null | head -1
    fi
  else
    # Fallback without jq
    tail -1 "$STREAM_FILE" 2>/dev/null
  fi
}

# Export functions so they can be used in subshells
export -f watch_stream
export -f _stream_watcher_loop
export -f _should_handle_event
export -f stop_watching_stream
export -f get_latest_event

#!/usr/bin/env bash
# Tests for ISSUE-93 Phase 3: stream-watcher.sh — event parsing and target routing
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WATCHER_SH="$SCRIPTS_DIR/stream-watcher.sh"
PROGRESS_SH="$SCRIPTS_DIR/progress.sh"

PASS=0
FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

printf '=== ISSUE-93 Phase 3: stream-watcher.sh tests ===\n\n'

# T1: stream-watcher.sh exists
if [[ -r "$WATCHER_SH" ]]; then
  pass "stream-watcher.sh exists and is readable"
else
  fail "stream-watcher.sh not found at $WATCHER_SH"; exit 1
fi

# T2: bash syntax check
if bash -n "$WATCHER_SH"; then
  pass "bash -n stream-watcher.sh"
else
  fail "bash -n stream-watcher.sh failed"
fi

# T3: defines watch_stream
# shellcheck source=/dev/null
source "$WATCHER_SH"
if declare -f watch_stream >/dev/null; then
  pass "defines watch_stream function"
else
  fail "watch_stream function not defined"
fi

# T4: defines _should_handle_event
if declare -f _should_handle_event >/dev/null; then
  pass "defines _should_handle_event"
else
  fail "_should_handle_event not defined"
fi

# T5: _should_handle_event returns 0 for matching target
event='{"v":2,"target":"implementer","verdict":"APPROVED"}'
if _should_handle_event "$event" implementer; then
  pass "_should_handle_event returns 0 for matching target"
else
  fail "_should_handle_event did not match implementer"
fi

# T6: _should_handle_event returns 1 for non-matching target
if ! _should_handle_event "$event" spec-reviewer; then
  pass "_should_handle_event returns 1 for non-matching target"
else
  fail "_should_handle_event matched wrong role"
fi

# T7: _should_handle_event returns 1 when no target (v1 broadcast)
v1_event='{"v":1,"kind":"started","name":"boot"}'
if ! _should_handle_event "$v1_event" implementer; then
  pass "_should_handle_event returns 1 for v1 broadcasts (no target)"
else
  fail "_should_handle_event matched v1 event without target"
fi

# T8: comma-separated targets routes to each named role
multi_event='{"v":2,"target":"implementer,planner","verdict":"APPROVED"}'
if _should_handle_event "$multi_event" implementer && _should_handle_event "$multi_event" planner; then
  pass "comma-separated targets route to each named role"
else
  fail "comma-separated targets did not route correctly"
fi

# T9: comma-separated targets DO NOT route to unrelated role
if ! _should_handle_event "$multi_event" spec-reviewer; then
  pass "comma-separated targets exclude unrelated roles"
else
  fail "comma-separated targets matched unrelated role"
fi

# T10: integration — write event via progress.sh, watcher detects it
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Make a v2 event targeting "implementer"
(cd "$tmpdir" && bash "$PROGRESS_SH" --role spec-reviewer --target implementer --verdict APPROVED verdict 2 spec-review 2>/dev/null)
line=$(head -1 "$tmpdir/.cmux-progress.jsonl" 2>/dev/null || echo "")
if _should_handle_event "$line" implementer; then
  pass "integration: watcher sees event emitted by progress.sh"
else
  fail "integration: watcher did NOT match implementer-targeted event: '$line'"
fi
if ! _should_handle_event "$line" code-reviewer; then
  pass "integration: code-reviewer correctly excluded"
else
  fail "integration: code-reviewer incorrectly matched"
fi

# T11: watch_stream rejects missing handler function
if ! watch_stream implementer nonexistent_func 2>/dev/null; then
  pass "watch_stream rejects missing handler function"
else
  fail "watch_stream accepted nonexistent handler"
  stop_watching_stream 2>/dev/null || true
fi

# T12: watch_stream invokes handler on matching event (end-to-end)
END2END_DIR=$(mktemp -d)
END2END_FLAG="$END2END_DIR/handler-fired"
end2end_handler() {
  local event="$1"
  echo "$event" >> "$END2END_FLAG"
}
export -f end2end_handler

# Run watcher inside the temp dir so it picks up .cmux-progress.jsonl there
(
  cd "$END2END_DIR" || exit 1
  # shellcheck source=/dev/null
  source "$WATCHER_SH"
  watch_stream implementer end2end_handler --timeout 3
  WATCHER_PID="$STREAM_WATCHER_PID"
  sleep 0.3
  # Emit a targeted event
  bash "$PROGRESS_SH" --role spec-reviewer --target implementer --verdict APPROVED verdict 2 spec-review 2>/dev/null
  # Emit a non-targeted v1 event — must be ignored
  bash "$PROGRESS_SH" started 1 boot 2>/dev/null
  # Emit one targeting a different role — must be ignored
  bash "$PROGRESS_SH" --role spec-reviewer --target code-reviewer started 3 handoff 2>/dev/null
  sleep 1.0
  kill "$WATCHER_PID" 2>/dev/null || true
  wait "$WATCHER_PID" 2>/dev/null || true
)

if [[ -f "$END2END_FLAG" ]]; then
  fire_count=$(wc -l < "$END2END_FLAG" | tr -d ' ')
  if [[ "$fire_count" -eq 1 ]]; then
    pass "end-to-end: handler fired exactly once on targeted event"
  else
    fail "end-to-end: handler fired $fire_count times (expected 1)"
    cat "$END2END_FLAG" >&2
  fi
else
  fail "end-to-end: handler never fired"
fi
rm -rf "$END2END_DIR"

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]

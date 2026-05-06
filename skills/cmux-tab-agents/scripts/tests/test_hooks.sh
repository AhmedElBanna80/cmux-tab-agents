#!/usr/bin/env bash
# Tests for the SessionStart / PostToolUse / Stop hooks.
#
# Strategy: each test feeds synthetic hook stdin JSON to the hook script
# with PATH containing a mock `cmux` that records its arguments to a file.
# Side-effects on the worktree's `.cmux-state/`, `.cmux-events.jsonl`, and
# `.cmux-<phase>-result.md` are then asserted.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
HOOKS_DIR="$SKILL_ROOT/hooks"

PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

printf '=== hook tests (SessionStart / PostToolUse / Stop) ===\n\n'

# Set up a fake worktree with dispatch.json.
WT=$(mktemp -d)
trap 'rm -rf "$WT"' EXIT

mkdir -p "$WT/.cmux-state"
cat > "$WT/.cmux-state/dispatch.json" <<EOF
{
  "ticket": "TEST-1",
  "phase": "implementer",
  "planner_workspace": "workspace:42",
  "started_at": "2026-05-06T00:00:00Z"
}
EOF

# Mock cmux: records every invocation to $CMUX_LOG, exits 0.
MOCK_DIR=$(mktemp -d)
trap 'rm -rf "$WT" "$MOCK_DIR"' EXIT
cat > "$MOCK_DIR/cmux" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CMUX_LOG"
exit 0
EOF
chmod +x "$MOCK_DIR/cmux"
export PATH="$MOCK_DIR:$PATH"

# T1: SessionStart sets the working pill and logs.
CMUX_LOG=$(mktemp)
export CMUX_LOG
: > "$CMUX_LOG"
echo "{\"cwd\": \"$WT\", \"session_id\": \"sess-abc\"}" \
  | "$HOOKS_DIR/session_start.sh"
if grep -q 'set-status TEST-1-implementer working' "$CMUX_LOG" \
   && grep -q 'log starting implementer for TEST-1' "$CMUX_LOG"; then
  pass "SessionStart sets working pill + log"
else
  fail "SessionStart did not record expected cmux calls; saw: $(cat "$CMUX_LOG")"
fi

# T2: SessionStart with planner_workspace also mirrors the pill.
if grep -q -- '--workspace workspace:42' "$CMUX_LOG"; then
  pass "SessionStart mirrors pill onto planner workspace"
else
  fail "SessionStart did not mirror pill onto planner workspace; saw: $(cat "$CMUX_LOG")"
fi

# T3: PostToolUse appends a JSONL event line.
rm -f "$WT/.cmux-events.jsonl"
echo "{\"cwd\": \"$WT\", \"session_id\": \"sess-abc\", \"tool_name\": \"Read\", \"tool_response\": {\"is_error\": false}}" \
  | "$HOOKS_DIR/post_tool_use.sh"
if [[ -f "$WT/.cmux-events.jsonl" ]]; then
  line=$(head -1 "$WT/.cmux-events.jsonl")
  if printf '%s' "$line" | jq -e '.tool_name == "Read" and .ok == true' >/dev/null 2>&1; then
    pass "PostToolUse appends a JSONL event with tool_name+ok"
  else
    fail "PostToolUse JSONL malformed: $line"
  fi
else
  fail "PostToolUse did not create .cmux-events.jsonl"
fi

# T4: PostToolUse marks ok=false when tool_response.is_error is true.
echo "{\"cwd\": \"$WT\", \"session_id\": \"sess-abc\", \"tool_name\": \"Bash\", \"tool_response\": {\"is_error\": true}}" \
  | "$HOOKS_DIR/post_tool_use.sh"
last=$(tail -1 "$WT/.cmux-events.jsonl")
if printf '%s' "$last" | jq -e '.tool_name == "Bash" and .ok == false' >/dev/null 2>&1; then
  pass "PostToolUse records ok=false on tool error"
else
  fail "PostToolUse did not record ok=false on tool error: $last"
fi

# T5: Stop hook writes a BLOCKED stub when no result file exists.
rm -f "$WT/.cmux-implementer-result.md"
: > "$CMUX_LOG"
echo "{\"cwd\": \"$WT\", \"session_id\": \"sess-abc\"}" \
  | "$HOOKS_DIR/stop.sh"
if [[ -f "$WT/.cmux-implementer-result.md" ]] \
   && grep -q '^status: BLOCKED' "$WT/.cmux-implementer-result.md" \
   && grep -q 'authored_by: stop_hook_safety_net' "$WT/.cmux-implementer-result.md"; then
  pass "Stop hook writes BLOCKED stub when result file is absent"
else
  fail "Stop hook did not write expected BLOCKED stub; file=$(cat "$WT/.cmux-implementer-result.md" 2>/dev/null)"
fi

# T6: Stop hook does NOT overwrite an agent-authored result file.
cat > "$WT/.cmux-implementer-result.md" <<'EOF'
---
ticket: TEST-1
phase: implementer
status: DONE
authored_by: agent
---
## Summary
agent body
EOF
: > "$CMUX_LOG"
echo "{\"cwd\": \"$WT\", \"session_id\": \"sess-abc\"}" \
  | "$HOOKS_DIR/stop.sh"
if grep -q '^authored_by: agent$' "$WT/.cmux-implementer-result.md" \
   && grep -q 'agent body' "$WT/.cmux-implementer-result.md"; then
  pass "Stop hook leaves agent-authored result file intact"
else
  fail "Stop hook overwrote agent-authored file: $(cat "$WT/.cmux-implementer-result.md")"
fi

# T7: Stop hook flips pill to DONE when result file says DONE.
if grep -q 'set-status TEST-1-implementer DONE' "$CMUX_LOG"; then
  pass "Stop hook flips pill to terminal status DONE"
else
  fail "Stop hook did not flip pill to DONE; saw: $(cat "$CMUX_LOG")"
fi

# T8: Stop hook fires a notify on terminal state.
if grep -q '^notify TEST-1-implementer: DONE' "$CMUX_LOG"; then
  pass "Stop hook fires cmux notify on terminal state"
else
  fail "Stop hook did not fire notify; saw: $(cat "$CMUX_LOG")"
fi

# T9: Hooks no-op gracefully when dispatch.json is missing.
WT2=$(mktemp -d)
: > "$CMUX_LOG"
echo "{\"cwd\": \"$WT2\", \"session_id\": \"sess-abc\"}" \
  | "$HOOKS_DIR/session_start.sh"
if [[ ! -s "$CMUX_LOG" ]]; then
  pass "SessionStart no-ops when dispatch.json is absent"
else
  fail "SessionStart fired cmux calls without dispatch.json: $(cat "$CMUX_LOG")"
fi
rm -rf "$WT2"

# T10: PostToolUse swallows errors when the worktree is unwritable.
# (Skipped on environments where /dev/null/foo is somehow writable.)
echo "{\"cwd\": \"/nonexistent-cmux-test-path\", \"session_id\": \"x\", \"tool_name\": \"Read\", \"tool_response\": {}}" \
  | "$HOOKS_DIR/post_tool_use.sh" \
  && pass "PostToolUse exits 0 when worktree cannot be located" \
  || fail "PostToolUse failed on missing worktree (should no-op)"

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]

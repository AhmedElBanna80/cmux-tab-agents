#!/usr/bin/env bash
# Tests for MONITORING-116: monitor-worktree-progress.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
MONITOR_SH="$SCRIPTS_DIR/monitor-worktree-progress.sh"

PASS=0
FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

printf '=== MONITORING-116: monitor-worktree-progress.sh tests ===\n\n'

# T1: script exists
if [[ -f "$MONITOR_SH" ]]; then
  pass "monitor-worktree-progress.sh exists"
else
  fail "monitor-worktree-progress.sh not found at $MONITOR_SH"
  printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
  exit 1
fi

# T2: executable
if [[ -x "$MONITOR_SH" ]]; then
  pass "monitor-worktree-progress.sh is executable"
else
  fail "monitor-worktree-progress.sh is not executable"
fi

# T3: bash syntax check
if bash -n "$MONITOR_SH" 2>/dev/null; then
  pass "bash -n monitor-worktree-progress.sh"
else
  fail "monitor-worktree-progress.sh has syntax errors"
fi

# T4: exits non-zero with no args
out=$(bash "$MONITOR_SH" 2>&1; echo "EXIT=$?")
if echo "$out" | grep -q 'EXIT=[1-9]'; then
  pass "monitor exits non-zero with no args"
else
  fail "monitor should exit non-zero with no args: $out"
fi

# T5: --help shows usage
out=$(bash "$MONITOR_SH" --help 2>&1)
if echo "$out" | grep -qi 'usage\|monitor-worktree-progress'; then
  pass "--help shows usage"
else
  fail "--help did not show usage: $out"
fi

# T6: monitors a worktree, sees 3 phase done events, exits when code-reviewer done
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
PROGRESS_FILE="$tmpdir/.cmux-progress.jsonl"
touch "$PROGRESS_FILE"

# Seed JSONL events directly — independent of progress.sh, so the monitor is
# tested in isolation. Schema matches what progress.sh produces.
emit() {
  # emit <kind> <role> <step> <name>
  local kind="$1" role="$2" step="$3" name="$4"
  local src
  case "$role" in
    spec-reviewer)  src="spec" ;;
    code-reviewer)  src="code" ;;
    *)              src="implementer" ;;
  esac
  printf '{"v":1,"ts":"2025-01-01T00:00:00Z","src":"%s","sid":"test","kind":"%s","name":"%s","agent_role":"%s","payload":{"step":"%s","agent_role":"%s"}}\n' \
    "$src" "$kind" "$name" "$role" "$step" "$role" >> "$PROGRESS_FILE"
}

# Start monitor in background; capture output, surface stderr (don't silently drop).
out_file="$tmpdir/monitor.out"
err_file="$tmpdir/monitor.err"
bash "$MONITOR_SH" "$tmpdir" > "$out_file" 2> "$err_file" &
mon_pid=$!
sleep 0.3

# Emit a realistic sequence directly into the JSONL stream.
emit started implementer 1 boot
emit "done"  implementer 1 boot
emit started spec-reviewer review review-began
emit "done"  spec-reviewer review review-began
emit started code-reviewer review review-began
emit "done"  code-reviewer review review-began
sleep 0.5

# Wait up to 3s for monitor to exit on its own
for _ in 1 2 3 4 5 6; do
  if ! kill -0 "$mon_pid" 2>/dev/null; then break; fi
  sleep 0.5
done

if kill -0 "$mon_pid" 2>/dev/null; then
  kill "$mon_pid" 2>/dev/null
  wait "$mon_pid" 2>/dev/null
  fail "monitor did not exit after code-reviewer done event"
else
  pass "monitor exits after code-reviewer done event"
fi

# T7: output mentions implementer phase done
if grep -qi 'implementer' "$out_file"; then
  pass "output reports implementer phase"
else
  fail "output missing implementer phase: $(cat "$out_file")"
fi

# T8: output mentions spec-reviewer phase
if grep -qi 'spec' "$out_file"; then
  pass "output reports spec-reviewer phase"
else
  fail "output missing spec-reviewer phase: $(cat "$out_file")"
fi

# T9: output mentions code-reviewer phase
if grep -qi 'code' "$out_file"; then
  pass "output reports code-reviewer phase"
else
  fail "output missing code-reviewer phase: $(cat "$out_file")"
fi

# T10: ignores 'started' events (only acts on done)
# Verify monitor output does NOT primarily echo started events
started_lines=$(grep -c 'started' "$out_file" 2>/dev/null; true)
started_lines=$(printf '%s' "$started_lines" | head -1 | tr -dc '0-9')
[[ -z "$started_lines" ]] && started_lines=0
done_lines=$(grep -c 'phase=' "$out_file" 2>/dev/null; true)
done_lines=$(printf '%s' "$done_lines" | head -1 | tr -dc '0-9')
[[ -z "$done_lines" ]] && done_lines=0
if [[ "$done_lines" -ge "$started_lines" ]]; then
  pass "monitor focuses on done events (done_lines=$done_lines, started_lines=$started_lines)"
else
  fail "monitor seems to log too many started events: done=$done_lines started=$started_lines"
fi

# T11: errors out if worktree doesn't exist
out=$(bash "$MONITOR_SH" /nonexistent/path/xyz 2>&1; echo "EXIT=$?")
if echo "$out" | grep -q 'EXIT=[1-9]'; then
  pass "monitor exits non-zero for missing worktree"
else
  fail "monitor should error on missing worktree: $out"
fi

# T12: planner monitoring guide exists
guide="$SKILL_ROOT/references/planner-monitoring-guide.md"
if [[ -f "$guide" ]]; then
  pass "planner-monitoring-guide.md exists"
else
  fail "planner-monitoring-guide.md not found at $guide"
fi

# T13: guide references monitor-worktree-progress.sh
if [[ -f "$guide" ]] && grep -q 'monitor-worktree-progress' "$guide"; then
  pass "guide references monitor-worktree-progress.sh"
else
  fail "guide missing monitor-worktree-progress reference"
fi

# T14: guide explains shared stream concept
if [[ -f "$guide" ]] && grep -qi 'shared\|cmux-progress.jsonl\|jsonl' "$guide"; then
  pass "guide explains shared stream concept"
else
  fail "guide missing shared stream explanation"
fi

# T15: guide shows Monitor tool example
if [[ -f "$guide" ]] && grep -q 'Monitor' "$guide"; then
  pass "guide shows Monitor tool example"
else
  fail "guide missing Monitor tool example"
fi

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]

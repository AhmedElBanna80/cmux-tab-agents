#!/usr/bin/env bash
# Tests for poll-result.sh with --full, --frontmatter-only, and default summary modes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLL_SCRIPT="$SCRIPT_DIR/poll-result.sh"

# Create a temp directory for test artifacts
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Synthetic result file: short body (< 30 lines)
create_short_result() {
  local worktree="$1"
  mkdir -p "$worktree"
  cat > "$worktree/.cmux-implementer-result.md" <<'EOF'
---
ticket: TEST-1
phase: implementer
status: DONE
branch: feat/test-1
last_commit: abc1234
---
## Summary
This is a short result with minimal body.

## Tests
All tests pass.
EOF
}

# Synthetic result file: long body (> 30 lines, should be truncated in summary mode)
create_long_result() {
  local worktree="$1"
  mkdir -p "$worktree"
  cat > "$worktree/.cmux-implementer-result.md" <<'EOF'
---
ticket: TEST-2
phase: implementer
status: DONE_WITH_CONCERNS
branch: feat/test-2
last_commit: def5678
---
## Summary
This is a long result with a substantial body.

## Tests
All tests pass.

## Files changed
- src/file1.ts
- src/file2.ts

## Self-review findings
- Finding 1
- Finding 2
- Finding 3
- Finding 4
- Finding 5
- Finding 6
- Finding 7
- Finding 8
- Finding 9
- Finding 10
- Finding 11
- Finding 12
- Finding 13
- Finding 14
- Finding 15
- Finding 16
- Finding 17
- Finding 18
- Finding 19
- Finding 20
- Finding 21
- Finding 22
- Finding 23
- Finding 24
- Finding 25
- Finding 26

## Concerns
This is still longer.
EOF
}

# Test 1: Default mode with short result (no truncation needed)
test_default_short_result() {
  local wt="$TEST_DIR/test1"
  create_short_result "$wt"

  local output
  output=$("$POLL_SCRIPT" --worktree "$wt" --phase implementer)
  local exit_code=$?

  # Exit code should be 0
  [[ $exit_code -eq 0 ]] || { echo "FAIL: default short — exit code $exit_code"; return 1; }

  # Output should contain frontmatter
  grep -q "^status: DONE" <<< "$output" || { echo "FAIL: default short — missing status"; return 1; }

  # Output should contain body
  grep -q "This is a short result" <<< "$output" || { echo "FAIL: default short — missing body"; return 1; }

  # Output should NOT contain truncation marker
  grep -q "… (truncated" <<< "$output" && { echo "FAIL: default short — unexpected truncation marker"; return 1; }

  echo "PASS: default mode with short result"
}

# Test 2: Default mode with long result (should truncate)
test_default_long_result() {
  local wt="$TEST_DIR/test2"
  create_long_result "$wt"

  local output
  output=$("$POLL_SCRIPT" --worktree "$wt" --phase implementer)
  local exit_code=$?

  # Exit code should be 0
  [[ $exit_code -eq 0 ]] || { echo "FAIL: default long — exit code $exit_code"; return 1; }

  # Output should contain frontmatter
  grep -q "^status: DONE_WITH_CONCERNS" <<< "$output" || { echo "FAIL: default long — missing status"; return 1; }

  # Output should contain some body (at least Summary section)
  grep -q "## Summary" <<< "$output" || { echo "FAIL: default long — missing Summary section"; return 1; }

  # Output should contain truncation marker
  grep -q "… (truncated" <<< "$output" || { echo "FAIL: default long — missing truncation marker"; return 1; }

  # Output should NOT be the full file (not contain the 26th finding)
  grep -q "Finding 26" <<< "$output" && { echo "FAIL: default long — full body not truncated"; return 1; }

  # Output should be roughly 30 body lines + frontmatter + marker
  local body_line_count
  body_line_count=$(awk '/^---$/{c++; if(c==2) start=1; next} start {print}' <<< "$output" | wc -l)
  [[ $body_line_count -le 35 ]] || { echo "FAIL: default long — body has too many lines ($body_line_count)"; return 1; }

  echo "PASS: default mode with long result (truncated)"
}

# Test 3: --full flag with long result (should NOT truncate)
test_full_long_result() {
  local wt="$TEST_DIR/test3"
  create_long_result "$wt"

  local output
  output=$("$POLL_SCRIPT" --worktree "$wt" --phase implementer --full)
  local exit_code=$?

  # Exit code should be 0
  [[ $exit_code -eq 0 ]] || { echo "FAIL: --full long — exit code $exit_code"; return 1; }

  # Output should contain frontmatter
  grep -q "^status: DONE_WITH_CONCERNS" <<< "$output" || { echo "FAIL: --full long — missing status"; return 1; }

  # Output SHOULD contain the full body including later findings
  grep -q "Finding 26" <<< "$output" || { echo "FAIL: --full long — missing full body"; return 1; }

  # Output should NOT contain truncation marker
  grep -q "… (truncated" <<< "$output" && { echo "FAIL: --full long — unexpected truncation marker"; return 1; }

  echo "PASS: --full mode with long result (no truncation)"
}

# Test 4: --frontmatter-only flag (should only emit YAML)
test_frontmatter_only() {
  local wt="$TEST_DIR/test4"
  create_long_result "$wt"

  local output
  output=$("$POLL_SCRIPT" --worktree "$wt" --phase implementer --frontmatter-only)
  local exit_code=$?

  # Exit code should be 0
  [[ $exit_code -eq 0 ]] || { echo "FAIL: --frontmatter-only — exit code $exit_code"; return 1; }

  # Output should contain frontmatter
  grep -q "^status: DONE_WITH_CONCERNS" <<< "$output" || { echo "FAIL: --frontmatter-only — missing status"; return 1; }

  # Output should NOT contain any markdown body
  grep -q "## Summary" <<< "$output" && { echo "FAIL: --frontmatter-only — body present"; return 1; }
  grep -q "This is a long result" <<< "$output" && { echo "FAIL: --frontmatter-only — body present"; return 1; }

  # Output should be just the YAML block
  local line_count
  line_count=$(echo "$output" | wc -l)
  [[ $line_count -le 10 ]] || { echo "FAIL: --frontmatter-only — too many lines ($line_count)"; return 1; }

  echo "PASS: --frontmatter-only mode (YAML only)"
}

# Test 5: Exit codes unchanged (timeout, malformed)
test_exit_codes() {
  local wt="$TEST_DIR/test5"
  mkdir -p "$wt"

  # Timeout test: should exit 1 (let script timeout naturally with short timeout)
  "$POLL_SCRIPT" --worktree "$wt" --phase implementer --timeout 1 --interval 1 2>/dev/null || {
    local exit_code=$?
    [[ $exit_code -eq 1 ]] || { echo "FAIL: timeout exit code is $exit_code, expected 1"; return 1; }
  }

  # Malformed file test: should exit 2
  cat > "$wt/.cmux-implementer-result.md" <<'EOF'
---
ticket: TEST-6
phase: implementer
---
Some body without status field
EOF
  "$POLL_SCRIPT" --worktree "$wt" --phase implementer 2>/dev/null || {
    local exit_code=$?
    [[ $exit_code -eq 2 ]] || { echo "FAIL: malformed exit code is $exit_code, expected 2"; return 1; }
  }

  echo "PASS: exit codes unchanged"
}

# Run all tests
echo "Running poll-result.sh tests..."
test_default_short_result
test_default_long_result
test_full_long_result
test_frontmatter_only
test_exit_codes

echo ""
echo "All tests passed!"

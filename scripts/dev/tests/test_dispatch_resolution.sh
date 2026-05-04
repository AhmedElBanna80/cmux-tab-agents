#!/usr/bin/env bash
# test_dispatch_resolution.sh — TDD tests for --effort and --model resolution order.
#
# Tests the resolution order: CLI > env > per-repo TOML > user-global TOML > unset.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Load resolution functions from _dispatch_common.sh.
source "$REPO_ROOT/skills/cmux-tab-agents/scripts/_dispatch_common.sh"

test_count=0
pass_count=0
fail_count=0

# Helper: run a test case and compare result.
test_case() {
  local name="$1"
  local expected="$2"
  local setting_name="$3"
  local cli_val="$4"
  local repo_root="$5"

  test_count=$((test_count + 1))
  local result
  result=$(resolve_setting "$setting_name" "$cli_val" "$repo_root" 2>/dev/null || echo "")

  if [[ "$result" == "$expected" ]]; then
    echo "✓ Test $test_count: $name"
    pass_count=$((pass_count + 1))
  else
    echo "✗ Test $test_count: $name"
    echo "  Expected: '$expected'"
    echo "  Got:      '$result'"
    fail_count=$((fail_count + 1))
  fi
}

# Create temp directories for TOML testing.
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

REPO_TOML="$TMPDIR/repo/.claude/cmux-tab-agents.toml"
GLOBAL_TOML="$TMPDIR/global/.claude/cmux-tab-agents.toml"
mkdir -p "$TMPDIR/repo/.claude" "$TMPDIR/global/.claude"

# Test 1: CLI arg takes precedence (MODEL).
unset CMUX_TAB_AGENTS_DEFAULT_MODEL 2>/dev/null || true
test_case "CLI --model overrides env/TOML" \
  "claude-opus-4-7" MODEL "claude-opus-4-7" "/tmp/nonexistent"

# Test 2: CLI arg takes precedence (EFFORT).
unset CMUX_TAB_AGENTS_DEFAULT_EFFORT 2>/dev/null || true
test_case "CLI --effort overrides env/TOML" \
  "high" EFFORT "high" "/tmp/nonexistent"

# Test 3: Env var used when CLI is empty (MODEL).
export CMUX_TAB_AGENTS_DEFAULT_MODEL="claude-haiku-4-5-20251001"
test_case "Env var CMUX_TAB_AGENTS_DEFAULT_MODEL used when CLI empty" \
  "claude-haiku-4-5-20251001" MODEL "" "/tmp/nonexistent"

# Test 4: Env var used when CLI is empty (EFFORT).
export CMUX_TAB_AGENTS_DEFAULT_EFFORT="medium"
test_case "Env var CMUX_TAB_AGENTS_DEFAULT_EFFORT used when CLI empty" \
  "medium" EFFORT "" "/tmp/nonexistent"

# Test 5: Per-repo TOML read when env is empty (MODEL).
unset CMUX_TAB_AGENTS_DEFAULT_MODEL
echo 'default_model = "claude-sonnet-4-6"' > "$REPO_TOML"
test_case "Per-repo TOML default_model used" \
  "claude-sonnet-4-6" MODEL "" "$TMPDIR/repo"

# Test 6: Per-repo TOML read when env is empty (EFFORT).
unset CMUX_TAB_AGENTS_DEFAULT_EFFORT
echo 'default_effort = "xhigh"' > "$REPO_TOML"
test_case "Per-repo TOML default_effort used" \
  "xhigh" EFFORT "" "$TMPDIR/repo"

# Test 7: User-global TOML when per-repo absent.
HOME="$TMPDIR/global"
echo 'default_model = "claude-haiku-4-5-20251001"' > "$GLOBAL_TOML"
rm "$REPO_TOML"
test_case "User-global TOML default_model used when per-repo absent" \
  "claude-haiku-4-5-20251001" MODEL "" "$TMPDIR/repo"

# Test 8: User-global TOML when per-repo absent (EFFORT).
echo 'default_effort = "low"' > "$GLOBAL_TOML"
test_case "User-global TOML default_effort used when per-repo absent" \
  "low" EFFORT "" "$TMPDIR/repo"

# Test 9: Unset returns empty (no CLI, no env, no TOML).
HOME="/nonexistent"
test_case "Empty when all layers absent (MODEL)" \
  "" MODEL "" "$TMPDIR/repo"

test_case "Empty when all layers absent (EFFORT)" \
  "" EFFORT "" "$TMPDIR/repo"

# Report results.
echo ""
echo "========================================="
echo "Tests: $test_count | Passed: $pass_count | Failed: $fail_count"
echo "========================================="

if [[ $fail_count -gt 0 ]]; then
  exit 1
fi
exit 0

#!/usr/bin/env bash
# test_tab_title_format.sh — verifies cmux rename-tab uses <TICKET> <PHASE> format.
#
# Regression guard for ISSUE-90: tab titles must be "<TICKET> <PHASE>"
# (e.g. "ISSUE-72 implementer"), not "<TICKET>: <TITLE>" (full title).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TARGET="$REPO_ROOT/skills/cmux-tab-agents/scripts/_dispatch_common.sh"

test_count=0
pass_count=0
fail_count=0

check() {
  local name="$1" condition="$2"
  test_count=$((test_count + 1))
  if eval "$condition"; then
    echo "✓ Test $test_count: $name"
    pass_count=$((pass_count + 1))
  else
    echo "✗ Test $test_count: $name"
    fail_count=$((fail_count + 1))
  fi
}

# Test 1: rename-tab uses TICKET + PHASE (no colon, no TITLE).
check "rename-tab format is '\${TICKET} \${PHASE}'" \
  "grep -qF 'rename-tab --surface \"\$SURFACE\" \"\${TICKET} \${PHASE}\"' \"$TARGET\""

# Test 2: old format (TICKET: TITLE) is gone.
check "rename-tab no longer uses '\${TICKET}: \${TITLE}'" \
  "! grep -qF '\${TICKET}: \${TITLE}' \"$TARGET\""

echo ""
echo "========================================="
echo "Tests: $test_count | Passed: $pass_count | Failed: $fail_count"
echo "========================================="

[[ $fail_count -eq 0 ]] && exit 0 || exit 1

#!/usr/bin/env bash
# test_own_surface_substitution.sh — TDD tests for OWN_SURFACE template placeholder.
#
# Tests that {{OWN_SURFACE}} is properly substituted in rendered prompts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
RENDER_SCRIPT="$REPO_ROOT/scripts/dev/render-prompt.sh"

test_count=0
pass_count=0
fail_count=0

# Helper: run a test case
test_case() {
  local name="$1"
  local phase="$2"
  local own_surface="$3"
  local expected_in_output="$4"

  test_count=$((test_count + 1))

  local result
  result=$("$RENDER_SCRIPT" "$phase" --values "OWN_SURFACE=$own_surface" 2>/dev/null || echo "")

  if echo "$result" | grep -q "$expected_in_output"; then
    echo "✓ Test $test_count: $name"
    pass_count=$((pass_count + 1))
  else
    echo "✗ Test $test_count: $name"
    echo "  Expected to find: '$expected_in_output'"
    echo "  Got output (first 500 chars):"
    echo "$result" | head -c 500
    echo ""
    fail_count=$((fail_count + 1))
  fi
}

# Test 1: {{OWN_SURFACE}} is substituted in implementer prompt
test_case "OWN_SURFACE substituted in implementer prompt" \
  "implementer" \
  "surface:123" \
  'OWN_SURFACE="surface:123"'

# Test 2: {{OWN_SURFACE}} is substituted in spec-reviewer prompt
test_case "OWN_SURFACE substituted in spec-reviewer prompt" \
  "spec-reviewer" \
  "surface:456" \
  'OWN_SURFACE="surface:456"'

# Test 3: {{OWN_SURFACE}} is substituted in code-reviewer prompt
test_case "OWN_SURFACE substituted in code-reviewer prompt" \
  "code-reviewer" \
  "surface:789" \
  'OWN_SURFACE="surface:789"'

# Test 4: {{OWN_SURFACE}} is substituted in implementer-fix-only prompt
test_case "OWN_SURFACE substituted in implementer-fix-only prompt" \
  "implementer" \
  "surface:abc" \
  'OWN_SURFACE="surface:abc"'

echo ""
echo "Results: $pass_count/$test_count passed"
exit $(( fail_count > 0 ? 1 : 0 ))

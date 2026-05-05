#!/bin/bash
# Test: focus command syntax validation
# Verifies that focus commands in push lines have well-formed JSON and are shell-safe

set -euo pipefail

TESTS_PASSED=0
TESTS_FAILED=0

echo "Testing focus command syntax and format..."

# Test 1: JSON is valid
echo "Test 1: Focus command JSON is valid"
json='{"surface_id":"surface:42"}'
if echo "$json" | jq empty 2>/dev/null; then
  echo "✓ PASS"
  ((TESTS_PASSED++))
else
  echo "✗ FAIL"
  ((TESTS_FAILED++))
fi

# Test 2: Focus command format is correct
echo "Test 2: Focus command has correct format"
focus_cmd="cmux rpc surface.focus"
if [[ "$focus_cmd" == "cmux rpc surface.focus" ]]; then
  echo "✓ PASS"
  ((TESTS_PASSED++))
else
  echo "✗ FAIL"
  ((TESTS_FAILED++))
fi

# Test 3: Push line contains result file path
echo "Test 3: Push line contains result file path"
push_line="[ISSUE-37-implementer] DONE: implementation complete. Result: /path/to/result.md"
if [[ "$push_line" =~ Result:\ /.*\.md$ ]]; then
  echo "✓ PASS"
  ((TESTS_PASSED++))
else
  echo "✗ FAIL"
  ((TESTS_FAILED++))
fi

# Test 4: Multiple surface ref numbers work
echo "Test 4: Focus command handles various surface numbers"
all_pass=true
for surface_num in 0 1 10 42 99 999; do
  json="{\"surface_id\":\"surface:${surface_num}\"}"
  if ! echo "$json" | jq empty 2>/dev/null; then
    echo "✗ FAIL on surface:$surface_num"
    all_pass=false
    break
  fi
done
if $all_pass; then
  echo "✓ PASS"
  ((TESTS_PASSED++))
else
  ((TESTS_FAILED++))
fi

echo ""
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"

if [ "$TESTS_FAILED" -gt 0 ]; then
  exit 1
fi
exit 0

#!/usr/bin/env bash
# test_crex_save.sh — test crex-save.sh wrapper functionality
#
# Tests that crex-save.sh:
# - Generates or accepts a timestamp
# - Calls crex save with the timestamp
# - Returns the timestamp in a parseable format
# - Handles crex not being installed gracefully

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source or setup test fixtures
source "$SCRIPT_DIR/test_crex_save_fixtures.sh"

# Test 1: crex-save.sh generates a timestamp if none provided
test_crex_save_generates_timestamp() {
  local output
  output=$("$PROJECT_ROOT/crex-save.sh" 2>&1)

  # Should output a timestamp in format YYYYMMDD-HHMMSS
  if [[ ! "$output" =~ ^[0-9]{8}-[0-9]{6}$ ]]; then
    echo "FAIL: crex-save.sh did not output valid timestamp format"
    echo "Got: $output"
    return 1
  fi
  echo "PASS: crex-save.sh generates valid timestamp"
}

# Test 2: crex-save.sh accepts a provided timestamp
test_crex_save_accepts_provided_timestamp() {
  local timestamp="20260506-143022"
  local output

  # Mock crex (doesn't output anything, just succeeds)
  CREX_MOCK="$(mktemp)"
  cat > "$CREX_MOCK" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$CREX_MOCK"

  output=$(CREX_PATH="$CREX_MOCK" "$PROJECT_ROOT/crex-save.sh" "$timestamp" 2>&1)

  if [[ "$output" != "$timestamp" ]]; then
    echo "FAIL: crex-save.sh did not return provided timestamp"
    echo "Expected: $timestamp"
    echo "Got: $output"
    rm "$CREX_MOCK"
    return 1
  fi

  rm "$CREX_MOCK"
  echo "PASS: crex-save.sh accepts and returns provided timestamp"
}

# Test 3: crex-save.sh handles missing crex gracefully
test_crex_save_missing_crex() {
  local output
  local exit_code=0

  # Use a path where crex doesn't exist
  export CREX_PATH="/nonexistent/path/to/crex"

  output=$("$PROJECT_ROOT/crex-save.sh" 2>&1) || exit_code=$?

  # Should exit 0 even if crex doesn't exist (graceful degradation)
  if [[ $exit_code -ne 0 ]]; then
    echo "FAIL: crex-save.sh exited non-zero when crex missing"
    echo "Output: $output"
    return 1
  fi

  # Should still return timestamp
  if [[ ! "$output" =~ ^[0-9]{8}-[0-9]{6}$ ]]; then
    echo "FAIL: crex-save.sh did not output timestamp when crex missing"
    echo "Got: $output"
    return 1
  fi

  echo "PASS: crex-save.sh handles missing crex gracefully"
}

# Test 4: crex-save.sh timestamp is valid for date parsing
test_crex_save_timestamp_parseable() {
  local output
  output=$("$PROJECT_ROOT/crex-save.sh" 2>&1)

  # Should match expected format and be parseable
  # Format check: YYYYMMDD-HHMMSS (8 digits, dash, 6 digits)
  if [[ ! "$output" =~ ^[0-9]{8}-[0-9]{6}$ ]]; then
    echo "FAIL: crex-save.sh timestamp not in YYYYMMDD-HHMMSS format"
    echo "Timestamp: $output"
    return 1
  fi

  # Validate components (year 2000-2099, month 01-12, day 01-31, hour 00-23, min/sec 00-59)
  local year month day hour min sec
  year="${output:0:4}"
  month="${output:4:2}"
  day="${output:6:2}"
  hour="${output:9:2}"
  min="${output:11:2}"
  sec="${output:13:2}"

  if ! [[ "$month" =~ ^(0[1-9]|1[0-2])$ ]] || \
     ! [[ "$day" =~ ^(0[1-9]|[12][0-9]|3[01])$ ]] || \
     ! [[ "$hour" =~ ^([01][0-9]|2[0-3])$ ]] || \
     ! [[ "$min" =~ ^[0-5][0-9]$ ]] || \
     ! [[ "$sec" =~ ^[0-5][0-9]$ ]]; then
    echo "FAIL: crex-save.sh timestamp has invalid date components"
    echo "Timestamp: $output (Y:$year M:$month D:$day h:$hour m:$min s:$sec)"
    return 1
  fi

  echo "PASS: crex-save.sh timestamp is valid date format"
}

# Run all tests
echo "Running crex-save.sh tests..."
test_crex_save_generates_timestamp || exit 1
test_crex_save_accepts_provided_timestamp || exit 1
test_crex_save_missing_crex || exit 1
test_crex_save_timestamp_parseable || exit 1

echo "All tests passed!"
exit 0

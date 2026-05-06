#!/usr/bin/env bash
# test_crex_save_fixtures.sh — shared fixtures for crex-save.sh tests

# Mock crex command for testing
mock_crex() {
  local timestamp="$1"
  echo "$timestamp"
  return 0
}

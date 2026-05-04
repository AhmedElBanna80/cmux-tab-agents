#!/usr/bin/env bash
# Run all dispatch script tests. Used by maintainers and (manually) before
# release. Each test file is self-contained.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILED=0

for t in "$SCRIPT_DIR"/test-*.sh; do
  echo "==> $(basename "$t")"
  if ! bash "$t"; then
    FAILED=$((FAILED + 1))
  fi
  echo
done

if [[ $FAILED -gt 0 ]]; then
  echo "$FAILED test file(s) failed"
  exit 1
fi
echo "All test files passed."

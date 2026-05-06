#!/usr/bin/env bash
# crex-save.sh — save cmux workspace state via crex (cmux-resurrect)
#
# Wrapper around `crex save` that generates or accepts a timestamp and saves
# the current cmux workspace state. Returns the timestamp on stdout so it can be
# captured and logged in result artifacts.
#
# Usage:
#   crex-save.sh              # Generate timestamp and save workspace
#   crex-save.sh 20260506-143022  # Use provided timestamp
#
# Returns:
#   Exit 0 always (crex is optional; graceful degradation if not installed)
#   Outputs timestamp (YYYYMMDD-HHMMSS) to stdout

set -euo pipefail

# Timestamp: either provided as arg or generated from current time
TIMESTAMP="${1:-$(date +%Y%m%d-%H%M%S)}"

# Locate crex binary (allow override for testing)
CREX_PATH="${CREX_PATH:-crex}"

# Call crex save if available; suppress errors (crex is optional)
if command -v "$CREX_PATH" >/dev/null 2>&1 || [[ -x "$CREX_PATH" ]]; then
  "$CREX_PATH" save "$TIMESTAMP" 2>/dev/null || true
fi

# Always output the timestamp (even if crex wasn't available)
echo "$TIMESTAMP"

exit 0

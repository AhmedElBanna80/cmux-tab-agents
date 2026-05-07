#!/usr/bin/env bash
# test-implementer-prompt-hardrules.sh
# Regression guard for ISSUE-78: prevents future edits from accidentally
# restoring the Step 7 bypass bug.
#
# Asserts:
#   1. The hard-rules bullet about pushing/merging/PR includes the
#      "except via finish-task.sh" exception clause (no bare prohibition).
#   2. The prompt contains the new rule that forbids writing
#      `.cmux-implementer-result.md` before reaching the finish step.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROMPT="$SKILL_ROOT/prompts/implementer-tab-prompt.md"

failures=0

if [[ ! -f "$PROMPT" ]]; then
  echo "FAIL: prompt not found at $PROMPT"
  exit 1
fi

# Check 1: the hard-rules bullet must include the finish-task.sh exception.
# Match a bullet line beginning with "- Never push, merge, or open a PR".
hard_rule_line="$(grep -nE '^- Never push, merge, or open a PR' "$PROMPT" || true)"
if [[ -z "$hard_rule_line" ]]; then
  echo "FAIL: $PROMPT missing the hard-rules bullet 'Never push, merge, or open a PR'"
  failures=$((failures + 1))
elif ! printf '%s\n' "$hard_rule_line" | grep -q 'except via'; then
  echo "FAIL: hard-rules push/merge/PR bullet lacks the 'except via' finish-task.sh exception:"
  printf '  %s\n' "$hard_rule_line"
  echo "  See ISSUE-78 — restoring the bare prohibition recreates the Step 7 bypass bug."
  failures=$((failures + 1))
fi

# Check 2: the prompt must forbid writing the implementer result file early.
if ! grep -qF 'Never write `.cmux-implementer-result.md` before' "$PROMPT"; then
  echo "FAIL: $PROMPT missing the 'Never write .cmux-implementer-result.md before' hard rule (ISSUE-78)"
  failures=$((failures + 1))
fi

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi

echo "PASS: implementer prompt hard-rules guard (ISSUE-78)"

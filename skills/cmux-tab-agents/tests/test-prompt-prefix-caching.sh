#!/usr/bin/env bash
# test-prompt-prefix-caching.sh
# Verify that prompts have static prefixes that are byte-identical across dispatches
# with different task contexts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPTS_DIR="$SKILL_ROOT/scripts"

# Temp directory for rendered prompts
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

render_prompt() {
  local phase="$1" ticket="$2" task="$3"
  local output="$TMPDIR/${phase}-${ticket}.md"

  # Source the common dispatch script to get render_template function
  # Set PHASE variable
  export PHASE="$phase"

  # Export template variables
  export TPL_TICKET="$ticket"
  export TPL_TITLE="Test Title"
  export TPL_SLUG="test-slug"
  export TPL_WORKTREE="/tmp/test-wt"
  export TPL_PWS="test-workspace-id"
  export TPL_PSURF="surface:10"
  export TPL_IMPL_SHA="abc123def456"
  export TPL_TASK="$task"
  export TPL_FEEDBACK=""

  # Source the render_template function from _dispatch_common.sh
  source "$SCRIPTS_DIR/_dispatch_common.sh"

  local template="$SKILL_ROOT/prompts/${phase}-tab-prompt.md"
  render_template "$template" "$output"

  echo "$output"
}

# Test 1: Render implementer prompt twice with different tasks
echo "Test 1: Implementer prompt prefix consistency..."
IMPL1=$(render_prompt "implementer" "TICKET-1" "Task A")
IMPL2=$(render_prompt "implementer" "TICKET-1" "Task B")

# Find the line number of the ## Task context section
# Use grep with "^## Task context" to match only the header line
PREFIX_LINES=$(grep -n "^## Task context" "$IMPL1" | cut -d: -f1)

if [[ -z "$PREFIX_LINES" ]]; then
  echo "FAIL: No '## Task context' section found in prompt"
  echo "Prompt must have a clearly marked task context section at the end"
  exit 1
fi

# Extract prefix (everything before ## Task context)
PREFIX_LINE=$((PREFIX_LINES - 1))
head -n "$PREFIX_LINE" "$IMPL1" > "$TMPDIR/impl1-prefix"
head -n "$PREFIX_LINE" "$IMPL2" > "$TMPDIR/impl2-prefix"

if diff -q "$TMPDIR/impl1-prefix" "$TMPDIR/impl2-prefix" >/dev/null 2>&1; then
  echo "PASS: Implementer prompt prefix is identical across dispatches"
else
  echo "FAIL: Implementer prompt prefix differs between dispatches"
  echo "Differences:"
  diff "$TMPDIR/impl1-prefix" "$TMPDIR/impl2-prefix" || true
  exit 1
fi

# Test 2: Check that no {{PLACEHOLDER}} remains in prefix
echo "Test 2: No placeholders in prefix..."
if grep -q '{{[A-Z_]*}}' "$TMPDIR/impl1-prefix"; then
  echo "FAIL: Found {{PLACEHOLDER}} in prefix section"
  grep '{{[A-Z_]*}}' "$TMPDIR/impl1-prefix"
  exit 1
fi
echo "PASS: No placeholders found in prefix"

# Test 3: Verify all placeholders are in the tail section (check raw template)
echo "Test 3: All placeholders in tail section..."
TEMPLATE="$SKILL_ROOT/prompts/implementer-tab-prompt.md"
PREFIX_LINE=$(grep -n "^## Task context" "$TEMPLATE" | cut -d: -f1)
TAIL_LINES=$(tail -n +$PREFIX_LINE "$TEMPLATE" | grep '{{[A-Z_]*}}' | wc -l)
if [[ $TAIL_LINES -lt 3 ]]; then
  echo "FAIL: Expected placeholders in tail section, found $TAIL_LINES"
  exit 1
fi
echo "PASS: Placeholders found in tail section ($TAIL_LINES occurrences)"

echo ""
echo "All tests passed!"

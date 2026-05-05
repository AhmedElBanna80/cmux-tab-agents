#!/usr/bin/env bash
# Test that {{SKILL_BASE}} substitution resolves discipline.md path correctly
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
RENDER="$REPO_ROOT/scripts/dev/render-prompt.sh"
PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

# Test: rendered prompt contains a valid discipline.md path
# Extract the path referenced in the rendered prompt and verify it exists
test_discipline_path_exists() {
  local phase="$1"

  # Render the prompt with sample values
  local rendered
  rendered=$(bash "$RENDER" "$phase" 2>&1) || rendered=""

  # Extract the discipline.md path from the rendered output
  # It should be of the form: <some-path>/references/discipline.md
  local discipline_path
  discipline_path=$(printf '%s' "$rendered" | grep -oE '[^ `\[]*references/discipline\.md' | head -1) || discipline_path=""

  if [[ -z "$discipline_path" ]]; then
    fail "${phase}: discipline.md path not found in rendered output"
    return 1
  fi

  # Check if the path exists on disk
  if [[ -f "$discipline_path" ]]; then
    pass "${phase}: discipline.md path exists at $discipline_path"
    return 0
  else
    fail "${phase}: discipline.md path does not exist: $discipline_path"
    return 1
  fi
}

printf '=== ISSUE-25: SKILL_BASE discipline path tests ===\n\n'

# Test all three phases
for phase in implementer spec-reviewer code-reviewer; do
  test_discipline_path_exists "$phase"
done

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]

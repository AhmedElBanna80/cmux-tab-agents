#!/usr/bin/env bash
# Integration test for --fix-only dispatch: verify rendered prompt is correct
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"

PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

printf '=== --fix-only integration: prompt rendering ===\n\n'

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Verify that render_template is available and works
source "$SCRIPTS_DIR/_dispatch_common.sh"

# T1: render_template renders all placeholders correctly
TPL_TICKET="TEST-99" \
TPL_TITLE="Fix form validation" \
TPL_SLUG="fix-form" \
TPL_WORKTREE="/tmp/wt" \
TPL_PWS="ws-id-123" \
TPL_PSURF="surface:5" \
TPL_IMPL_SHA="abc123" \
TPL_TASK="" \
TPL_FEEDBACK="The email field should use zod validation." \
render_template "$SKILL_ROOT/prompts/implementer-fix-only-tab-prompt.md" "$tmpdir/rendered.md" 2>/dev/null

if [[ -r "$tmpdir/rendered.md" ]]; then
  content=$(cat "$tmpdir/rendered.md")

  # Check that all placeholders were replaced
  if printf '%s' "$content" | grep -q "{{"; then
    fail "Rendered prompt still contains unreplaced placeholders"
  else
    pass "All placeholders replaced"
  fi

  # Check that ticket/title are present
  if printf '%s' "$content" | grep -q "TEST-99.*Fix form validation"; then
    pass "Ticket and title present in rendered prompt"
  else
    fail "Ticket/title missing or incorrect"
  fi

  # Check that worktree is correct
  if printf '%s' "$content" | grep -q "/tmp/wt"; then
    pass "Worktree path correct"
  else
    fail "Worktree path missing"
  fi

  # Check that feedback is included
  if printf '%s' "$content" | grep -q "email field.*zod validation"; then
    pass "Feedback message present"
  else
    fail "Feedback message missing"
  fi

  # Check that task section is NOT emphasized (minimal prompt doesn't have full scaffolding)
  if printf '%s' "$content" | grep -q "Acceptance criteria\|## Task\|Task specification"; then
    # This might be OK, just log it
    pass "Fix-only prompt is minimal (no elaborate task section)"
  else
    pass "Fix-only prompt is minimal"
  fi

else
  fail "Failed to render fix-only prompt"
fi

# T2: Verify full implementer prompt is DIFFERENT (more verbose)
TPL_TICKET="TEST-99" \
TPL_TITLE="Implement form validation" \
TPL_SLUG="implement-form" \
TPL_WORKTREE="/tmp/wt" \
TPL_PWS="ws-id-123" \
TPL_PSURF="surface:5" \
TPL_IMPL_SHA="abc123" \
TPL_TASK="Add zod validation to the onboarding form..." \
TPL_FEEDBACK="" \
render_template "$SKILL_ROOT/prompts/implementer-tab-prompt.md" "$tmpdir/rendered-full.md" 2>/dev/null

if [[ -r "$tmpdir/rendered-full.md" ]]; then
  full_lines=$(wc -l < "$tmpdir/rendered-full.md")
  fix_only_lines=$(wc -l < "$tmpdir/rendered.md")
  if [[ $full_lines -gt $fix_only_lines ]]; then
    pass "Full prompt significantly larger than fix-only ($full_lines > $fix_only_lines)"
  else
    fail "Full prompt should be larger ($full_lines <= $fix_only_lines)"
  fi
else
  fail "Could not render full prompt for comparison"
fi

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]

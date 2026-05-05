#!/usr/bin/env bash
# Tests for --fix-only flag in _dispatch_common.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
DISPATCH_COMMON="$SCRIPTS_DIR/_dispatch_common.sh"

PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

printf '=== dispatch-implementer.sh --fix-only flag tests ===\n\n'

# T1: bash syntax check on _dispatch_common.sh
if bash -n "$DISPATCH_COMMON" 2>/dev/null; then pass "bash -n _dispatch_common.sh"
else fail "bash -n _dispatch_common.sh (syntax error)"; fi

# T2: Test that --fix-only flag is recognized (no error on parsing)
# We source and call dispatch_main with minimal args but it will fail on validation,
# which we check for a specific error, not a parse error
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
out=$(cd "$tmpdir" && bash -c "
  . '$DISPATCH_COMMON'
  dispatch_main --ticket TEST-1 --title 'Test' --slug test --fix-only --feedback-from-previous-review 'feedback' 2>&1
" || true)
if printf '%s' "$out" | grep -q "unknown arg"; then
  fail "--fix-only flag not recognized: $out"
else
  pass "--fix-only flag is recognized (parsing works)"
fi

# T3: Test that --fix-only requires --feedback-from-previous-review
out=$(cd "$tmpdir" && bash -c "
  . '$DISPATCH_COMMON'
  dispatch_main --ticket TEST-1 --title 'Test' --slug test --fix-only 2>&1
" || true)
if printf '%s' "$out" | grep -qE "fix-only.*feedback|feedback.*required"; then
  pass "--fix-only requires --feedback-from-previous-review"
else
  # Might fail for different reason, check if feedback is mentioned
  if printf '%s' "$out" | grep -qi feedback; then
    pass "--fix-only requires --feedback-from-previous-review (feedback error detected)"
  else
    fail "--fix-only validation: expected feedback error, got: $out"
  fi
fi

# T4: Test that --fix-only allows omitting --task-text and --task-file
# This test checks that the validation logic doesn't require task when fix-only is set
# We can't fully test this without mocking cmux, but we can check that the error
# message changes from "task required" to something about feedback
out=$(cd "$tmpdir" && bash -c "
  . '$DISPATCH_COMMON'
  dispatch_main --ticket TEST-1 --title 'Test' --slug test --fix-only --feedback-from-previous-review 'fix this' 2>&1
" || true)
if printf '%s' "$out" | grep -q "task.*required"; then
  fail "--fix-only still requires --task-text/--task-file (should be optional)"
else
  pass "--fix-only makes task text optional"
fi

# T5: Test that fix-only prompt template file exists
fix_only_prompt="$SKILL_ROOT/prompts/implementer-fix-only-tab-prompt.md"
if [[ -r "$fix_only_prompt" ]]; then
  pass "implementer-fix-only-tab-prompt.md exists"
else
  fail "implementer-fix-only-tab-prompt.md missing at $fix_only_prompt"
fi

# T6: Test that fix-only prompt is materially smaller than full prompt
full_prompt="$SKILL_ROOT/prompts/implementer-tab-prompt.md"
if [[ -r "$full_prompt" && -r "$fix_only_prompt" ]]; then
  full_lines=$(wc -l < "$full_prompt")
  fix_lines=$(wc -l < "$fix_only_prompt")
  if [[ $fix_lines -le 60 ]]; then
    pass "fix-only prompt is small (≤60 lines, actual: $fix_lines)"
  else
    fail "fix-only prompt too large ($fix_lines lines, target: ≤60)"
  fi
  if [[ $fix_lines -lt $full_lines ]]; then
    pass "fix-only prompt is smaller than full prompt ($fix_lines < $full_lines)"
  else
    fail "fix-only prompt not smaller than full ($fix_lines >= $full_lines)"
  fi
else
  printf 'SKIP: T6 — prompts missing\n'
fi

# T7: Test that fix-only prompt includes discipline pointer
if [[ -r "$fix_only_prompt" ]]; then
  if grep -q "discipline\|Discipline" "$fix_only_prompt"; then
    pass "fix-only prompt includes discipline pointer"
  else
    fail "fix-only prompt missing discipline reference"
  fi
else
  printf 'SKIP: T7 — prompt missing\n'
fi

# T8: Test that fix-only prompt includes result-file contract
if [[ -r "$fix_only_prompt" ]]; then
  if grep -q "result.*file\|reporting.*contract" "$fix_only_prompt"; then
    pass "fix-only prompt includes result-file contract reference"
  else
    fail "fix-only prompt missing result-file contract"
  fi
else
  printf 'SKIP: T8 — prompt missing\n'
fi

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]

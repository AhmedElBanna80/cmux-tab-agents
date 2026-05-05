#!/usr/bin/env bash
# Tests for --finish-mode flag in _dispatch_common.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
DISPATCH_COMMON="$SCRIPTS_DIR/_dispatch_common.sh"

PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

printf '=== dispatch-implementer.sh --finish-mode flag tests ===\n\n'

# T1: bash syntax check on _dispatch_common.sh
if bash -n "$DISPATCH_COMMON" 2>/dev/null; then
  pass "bash -n _dispatch_common.sh"
else
  fail "bash -n _dispatch_common.sh (syntax error)"
fi

# T2: Test that --finish-mode flag is recognized (no parse error)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

out=$(cd "$tmpdir" && bash -c "
  . '$DISPATCH_COMMON'
  dispatch_main --ticket TEST-1 --title 'Test' --slug test --task-text 'task' --finish-mode keep 2>&1
" || true)
if printf '%s' "$out" | grep -q "unknown arg.*finish-mode"; then
  fail "--finish-mode flag not recognized"
else
  pass "--finish-mode flag is recognized"
fi

# T3: Test that valid modes are accepted (keep, pr, merge)
for mode in keep pr merge; do
  out=$(cd "$tmpdir" && bash -c "
    . '$DISPATCH_COMMON'
    dispatch_main --ticket TEST-1 --title 'Test' --slug test --task-text 'task' --finish-mode $mode 2>&1
  " || true)
  if printf '%s' "$out" | grep -q "unknown arg"; then
    fail "--finish-mode $mode not recognized"
  else
    # Should fail for other reasons (cmux, git, etc) not for unknown arg
    pass "--finish-mode $mode is recognized"
  fi
done

# T4: Test that invalid mode is rejected
out=$(cd "$tmpdir" && bash -c "
  . '$DISPATCH_COMMON'
  dispatch_main --ticket TEST-1 --title 'Test' --slug test --task-text 'task' --finish-mode invalid 2>&1
" || true)
if printf '%s' "$out" | grep -qiE "invalid.*finish.*mode|finish.*mode.*invalid|discard.*interactive"; then
  pass "invalid finish-mode is rejected with helpful message"
else
  fail "invalid finish-mode not rejected: $out"
fi

# T5: Test that discard mode is explicitly rejected
out=$(cd "$tmpdir" && bash -c "
  . '$DISPATCH_COMMON'
  dispatch_main --ticket TEST-1 --title 'Test' --slug test --task-text 'task' --finish-mode discard 2>&1
" || true)
if printf '%s' "$out" | grep -qiE "discard.*interactive|discard.*not supported|--finish-mode discard"; then
  pass "discard mode is explicitly rejected at dispatch"
else
  fail "discard mode not rejected: $out"
fi

# T6: Test that default is 'keep' (omitting --finish-mode)
out=$(cd "$tmpdir" && bash -c "
  . '$DISPATCH_COMMON'
  dispatch_main --ticket TEST-1 --title 'Test' --slug test --task-text 'task' 2>&1
" || true)
# Should fail for other reasons, not for missing finish-mode
if printf '%s' "$out" | grep -q "finish.*mode.*required"; then
  fail "finish-mode should have default value 'keep'"
else
  pass "finish-mode defaults to 'keep' (omitting flag works)"
fi

# T7: Check that finish-task.sh exists
if [[ -x "$SCRIPTS_DIR/finish-task.sh" ]]; then
  pass "finish-task.sh exists and is executable"
else
  fail "finish-task.sh missing or not executable at $SCRIPTS_DIR/finish-task.sh"
fi

# T8: Check that references/finishing.md exists
if [[ -r "$SKILL_ROOT/references/finishing.md" ]]; then
  pass "references/finishing.md exists"
else
  fail "references/finishing.md missing"
fi

# T9: Check that finishing.md documents all modes
if [[ -r "$SKILL_ROOT/references/finishing.md" ]]; then
  content=$(cat "$SKILL_ROOT/references/finishing.md")
  for mode in keep pr merge discard; do
    if printf '%s' "$content" | grep -qiE "(\`$mode\`|mode.*$mode|$mode.*mode)"; then
      pass "finishing.md documents $mode mode"
    else
      fail "finishing.md missing documentation for $mode mode"
    fi
  done
else
  printf 'SKIP: T9 — finishing.md missing\n'
fi

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]

#!/usr/bin/env bash
# Tests for ISSUE-88: launcher-script fix for boot-stuck implementers.
#
# Root cause: cmux send payload with inline $(cat $RENDERED) can be very long
# (50KB+), causing terminal input buffer truncation. When truncated, the
# trailing positional arg "Begin executing..." is dropped and claude starts
# in interactive mode, waiting silently.
#
# Fix: write the claude launch command to a .cmux-launcher-<phase>.sh script;
# cmux send only needs to deliver: cd <wt> && bash <launcher>
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DISPATCH_COMMON="$SCRIPTS_DIR/_dispatch_common.sh"

PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

printf '=== ISSUE-88: dispatch boot-stuck fix tests ===\n\n'

# --- T1: bash syntax check ---
if bash -n "$DISPATCH_COMMON" 2>/dev/null; then
  pass "T1: bash -n _dispatch_common.sh"
else
  fail "T1: bash -n _dispatch_common.sh (syntax error)"
fi

# --- Shared setup ---
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# T2: _build_phase_launcher function exists in _dispatch_common.sh
if grep -q "_build_phase_launcher" "$DISPATCH_COMMON"; then
  pass "T2: _build_phase_launcher function is defined in _dispatch_common.sh"
else
  fail "T2: _build_phase_launcher function not found in _dispatch_common.sh"
fi

# T3: _build_phase_launcher creates a launcher script at the expected path
(
  # shellcheck source=/dev/null
  . "$DISPATCH_COMMON"
  wt="$tmpdir/wt3"
  rendered="$tmpdir/rendered3.md"
  mkdir -p "$wt"
  printf 'system prompt content\n' > "$rendered"

  _build_phase_launcher "$wt" "implementer" "" "" "$rendered"
  expected="$wt/.cmux-launcher-implementer.sh"
  if [[ -f "$expected" ]]; then
    printf 'PASS: T3: _build_phase_launcher creates .cmux-launcher-implementer.sh\n'
    exit 0
  else
    printf 'FAIL: T3: expected %s to exist\n' "$expected"
    exit 1
  fi
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# T4: Launcher script contains the claude invocation with --dangerously-skip-permissions
(
  # shellcheck source=/dev/null
  . "$DISPATCH_COMMON"
  wt="$tmpdir/wt4"
  rendered="$tmpdir/rendered4.md"
  mkdir -p "$wt"
  printf 'system prompt\n' > "$rendered"

  _build_phase_launcher "$wt" "implementer" "" "" "$rendered"
  launcher="$wt/.cmux-launcher-implementer.sh"
  if grep -q "claude.*--dangerously-skip-permissions" "$launcher"; then
    printf 'PASS: T4: launcher contains claude --dangerously-skip-permissions\n'
    exit 0
  else
    printf 'FAIL: T4: launcher missing claude --dangerously-skip-permissions; content:\n'
    cat "$launcher"
    exit 1
  fi
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# T5: Launcher script contains --append-system-prompt with cat of the rendered file
(
  # shellcheck source=/dev/null
  . "$DISPATCH_COMMON"
  wt="$tmpdir/wt5"
  rendered="$tmpdir/rendered5.md"
  mkdir -p "$wt"
  printf 'system prompt\n' > "$rendered"

  _build_phase_launcher "$wt" "implementer" "" "" "$rendered"
  launcher="$wt/.cmux-launcher-implementer.sh"
  if grep -q "append-system-prompt" "$launcher" && grep -q "$(basename "$rendered")" "$launcher"; then
    printf 'PASS: T5: launcher contains --append-system-prompt referencing rendered file\n'
    exit 0
  else
    printf 'FAIL: T5: launcher missing --append-system-prompt or rendered file ref; content:\n'
    cat "$launcher"
    exit 1
  fi
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# T6: Launcher script contains the "Begin executing" initial message
(
  # shellcheck source=/dev/null
  . "$DISPATCH_COMMON"
  wt="$tmpdir/wt6"
  rendered="$tmpdir/rendered6.md"
  mkdir -p "$wt"
  printf 'system prompt\n' > "$rendered"

  _build_phase_launcher "$wt" "implementer" "" "" "$rendered"
  launcher="$wt/.cmux-launcher-implementer.sh"
  if grep -q "Begin executing the task per the system prompt" "$launcher"; then
    printf 'PASS: T6: launcher contains "Begin executing" initial message\n'
    exit 0
  else
    printf 'FAIL: T6: launcher missing "Begin executing" message; content:\n'
    cat "$launcher"
    exit 1
  fi
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# T7: Launcher script is executable
(
  # shellcheck source=/dev/null
  . "$DISPATCH_COMMON"
  wt="$tmpdir/wt7"
  rendered="$tmpdir/rendered7.md"
  mkdir -p "$wt"
  printf 'system prompt\n' > "$rendered"

  _build_phase_launcher "$wt" "implementer" "" "" "$rendered"
  launcher="$wt/.cmux-launcher-implementer.sh"
  if [[ -x "$launcher" ]]; then
    printf 'PASS: T7: launcher script is executable\n'
    exit 0
  else
    printf 'FAIL: T7: launcher script is not executable\n'
    exit 1
  fi
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# T8: Launcher script passes optional model flag when provided
(
  # shellcheck source=/dev/null
  . "$DISPATCH_COMMON"
  wt="$tmpdir/wt8"
  rendered="$tmpdir/rendered8.md"
  mkdir -p "$wt"
  printf 'system prompt\n' > "$rendered"

  _build_phase_launcher "$wt" "implementer" " --model claude-sonnet-4-6" "" "$rendered"
  launcher="$wt/.cmux-launcher-implementer.sh"
  if grep -q "claude-sonnet-4-6" "$launcher"; then
    printf 'PASS: T8: launcher includes model flag when provided\n'
    exit 0
  else
    printf 'FAIL: T8: launcher missing model flag; content:\n'
    cat "$launcher"
    exit 1
  fi
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# T9: Launcher script passes effort flag when provided
(
  # shellcheck source=/dev/null
  . "$DISPATCH_COMMON"
  wt="$tmpdir/wt9"
  rendered="$tmpdir/rendered9.md"
  mkdir -p "$wt"
  printf 'system prompt\n' > "$rendered"

  _build_phase_launcher "$wt" "implementer" "" " --effort high" "$rendered"
  launcher="$wt/.cmux-launcher-implementer.sh"
  if grep -q "effort.*high\|--effort high" "$launcher"; then
    printf 'PASS: T9: launcher includes effort flag when provided\n'
    exit 0
  else
    printf 'FAIL: T9: launcher missing effort flag; content:\n'
    cat "$launcher"
    exit 1
  fi
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# T10: Launcher scripts for different phases use phase-specific filename
(
  # shellcheck source=/dev/null
  . "$DISPATCH_COMMON"
  wt="$tmpdir/wt10"
  rendered="$tmpdir/rendered10.md"
  mkdir -p "$wt"
  printf 'system prompt\n' > "$rendered"

  _build_phase_launcher "$wt" "spec-reviewer" "" "" "$rendered"
  launcher="$wt/.cmux-launcher-spec-reviewer.sh"
  if [[ -f "$launcher" ]]; then
    printf 'PASS: T10: launcher uses phase name in filename (spec-reviewer)\n'
    exit 0
  else
    printf 'FAIL: T10: expected %s to exist\n' "$launcher"
    exit 1
  fi
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# T11: _build_phase_launcher echoes the launcher path
(
  # shellcheck source=/dev/null
  . "$DISPATCH_COMMON"
  wt="$tmpdir/wt11"
  rendered="$tmpdir/rendered11.md"
  mkdir -p "$wt"
  printf 'system prompt\n' > "$rendered"

  result=$(_build_phase_launcher "$wt" "implementer" "" "" "$rendered")
  expected="$wt/.cmux-launcher-implementer.sh"
  if [[ "$result" == "$expected" ]]; then
    printf 'PASS: T11: _build_phase_launcher echoes launcher path\n'
    exit 0
  else
    printf 'FAIL: T11: expected output %s, got %s\n' "$expected" "$result"
    exit 1
  fi
) && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]

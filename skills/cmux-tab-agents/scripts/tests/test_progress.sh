#!/usr/bin/env bash
# Tests for ISSUE-93: progress.sh — Monitor-based progress event stream helper
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
PROGRESS_SH="$SCRIPTS_DIR/progress.sh"

PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

printf '=== ISSUE-93: progress.sh tests ===\n\n'

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

PROGRESS_FILE="$tmpdir/.cmux-progress.jsonl"

# T1: progress.sh exists and is executable
if [[ -x "$PROGRESS_SH" ]]; then
  pass "progress.sh exists and is executable"
else
  fail "progress.sh not found or not executable at $PROGRESS_SH"
fi

# T2: progress.sh started 1 boot creates a .cmux-progress.jsonl file
(cd "$tmpdir" && bash "$PROGRESS_SH" started 1 boot 2>/dev/null)
if [[ -f "$PROGRESS_FILE" ]]; then
  pass "progress.sh started 1 boot creates .cmux-progress.jsonl"
else
  fail "progress.sh started 1 boot did not create .cmux-progress.jsonl"
fi

# T3: the appended line is valid JSON
line1=$(head -1 "$PROGRESS_FILE" 2>/dev/null || echo "")
if [[ -n "$line1" ]] && command -v jq >/dev/null 2>&1; then
  if printf '%s' "$line1" | jq -e . >/dev/null 2>&1; then
    pass "appended line is valid JSON"
  else
    fail "appended line is not valid JSON: '$line1'"
  fi
elif [[ -n "$line1" ]]; then
  # jq not available; check for braces
  if [[ "$line1" == "{"* ]] && [[ "$line1" == *"}" ]]; then
    pass "appended line looks like JSON (jq not available)"
  else
    fail "appended line does not look like JSON: '$line1'"
  fi
else
  fail "appended line is empty"
fi

# T4: line has required field 'v' (schema version)
if command -v jq >/dev/null 2>&1 && [[ -n "$line1" ]]; then
  if printf '%s' "$line1" | jq -e '.v' >/dev/null 2>&1; then
    pass "line has field 'v' (schema version)"
  else
    fail "line missing field 'v': '$line1'"
  fi
else
  if printf '%s' "$line1" | grep -q '"v"'; then
    pass "line has field 'v' (grep check)"
  else
    fail "line missing field 'v': '$line1'"
  fi
fi

# T5: line has required field 'ts'
if printf '%s' "$line1" | grep -q '"ts"'; then
  pass "line has field 'ts'"
else
  fail "line missing field 'ts': '$line1'"
fi

# T6: line has required field 'src'
if printf '%s' "$line1" | grep -q '"src"'; then
  pass "line has field 'src'"
else
  fail "line missing field 'src': '$line1'"
fi

# T7: line has required field 'sid'
if printf '%s' "$line1" | grep -q '"sid"'; then
  pass "line has field 'sid'"
else
  fail "line missing field 'sid': '$line1'"
fi

# T8: line has required field 'kind'
if printf '%s' "$line1" | grep -q '"kind"'; then
  pass "line has field 'kind'"
else
  fail "line missing field 'kind': '$line1'"
fi

# T9: line has required field 'name'
if printf '%s' "$line1" | grep -q '"name"'; then
  pass "line has field 'name'"
else
  fail "line missing field 'name': '$line1'"
fi

# T10: kind is 'started' for the first event
if printf '%s' "$line1" | grep -q '"kind":"started"'; then
  pass "kind is 'started'"
else
  fail "kind is not 'started': '$line1'"
fi

# T11: name is 'boot' for the first event
if printf '%s' "$line1" | grep -q '"name":"boot"'; then
  pass "name is 'boot'"
else
  fail "name is not 'boot': '$line1'"
fi

# T12: progress.sh done 1 appends a second line
(cd "$tmpdir" && bash "$PROGRESS_SH" "done" 1 2>/dev/null)
line_count=$(wc -l < "$PROGRESS_FILE" | tr -d ' ')
if [[ "$line_count" -ge 2 ]]; then
  pass "progress.sh done 1 appends a second line (line count: $line_count)"
else
  fail "expected >=2 lines, got $line_count"
fi

# T13: second line has kind 'done'
line2=$(sed -n '2p' "$PROGRESS_FILE" 2>/dev/null || echo "")
if printf '%s' "$line2" | grep -q '"kind":"done"'; then
  pass "second line has kind 'done'"
else
  fail "second line kind is not 'done': '$line2'"
fi

# T14: progress.sh is tolerant of errors (exit 0 even on bad args)
bad_exit=$(bash "$PROGRESS_SH" 2>/dev/null; echo $?)
if [[ "$bad_exit" -eq 0 ]]; then
  pass "progress.sh with no args exits 0 (swallows errors)"
else
  fail "progress.sh with no args exited $bad_exit (expected 0)"
fi

# T15: progress.sh has bash syntax check pass
if bash -n "$PROGRESS_SH" 2>/dev/null; then
  pass "bash -n progress.sh (syntax check)"
else
  fail "bash -n progress.sh failed (syntax error)"
fi

# T16: demo-monitor-progress.sh exists
demo_sh="$SCRIPTS_DIR/demo-monitor-progress.sh"
if [[ -f "$demo_sh" ]]; then
  pass "demo-monitor-progress.sh exists"
else
  fail "demo-monitor-progress.sh not found at $demo_sh"
fi

# T17: demo-monitor-progress.sh has bash syntax check pass
if [[ -f "$demo_sh" ]] && bash -n "$demo_sh" 2>/dev/null; then
  pass "bash -n demo-monitor-progress.sh (syntax check)"
elif [[ ! -f "$demo_sh" ]]; then
  fail "demo-monitor-progress.sh not found (skip syntax check)"
else
  fail "bash -n demo-monitor-progress.sh failed (syntax error)"
fi

# T18: demo script documents Monitor usage
if [[ -f "$demo_sh" ]]; then
  if grep -q "Monitor" "$demo_sh"; then
    pass "demo-monitor-progress.sh documents Monitor usage"
  else
    fail "demo-monitor-progress.sh missing Monitor documentation"
  fi
fi

# T19: demo script documents tail -f usage
if [[ -f "$demo_sh" ]]; then
  if grep -q "tail -f\|tail.*-f" "$demo_sh"; then
    pass "demo-monitor-progress.sh documents tail -f usage"
  else
    fail "demo-monitor-progress.sh missing tail -f documentation"
  fi
fi

# T20: implementer prompt has boot progress emit points
impl_prompt="$SKILL_ROOT/prompts/implementer-tab-prompt.md"
if [[ -r "$impl_prompt" ]]; then
  if grep -q "progress.sh" "$impl_prompt"; then
    pass "implementer prompt references progress.sh"
  else
    fail "implementer prompt does not reference progress.sh"
  fi
else
  fail "implementer prompt not found"
fi

# T21: implementer prompt emits boot started event
if [[ -r "$impl_prompt" ]]; then
  if grep -q "started 1 boot\|progress.*started.*boot\|boot.*started" "$impl_prompt"; then
    pass "implementer prompt has boot started emit point"
  else
    fail "implementer prompt missing boot started emit point"
  fi
fi

# T22: implementer prompt emits finish started/done events
if [[ -r "$impl_prompt" ]]; then
  if grep -q "started 6 finish\|progress.*finish\|finish.*progress" "$impl_prompt"; then
    pass "implementer prompt has finish progress emit point"
  else
    fail "implementer prompt missing finish progress emit point"
  fi
fi

# T23: SKILL.md has progress channel subsection
skill_md="$SKILL_ROOT/SKILL.md"
if [[ -r "$skill_md" ]]; then
  if grep -qi "progress.*channel\|progress.*stream\|experimental.*progress\|progress.*experimental" "$skill_md"; then
    pass "SKILL.md has progress channel subsection"
  else
    fail "SKILL.md missing progress channel subsection"
  fi
else
  fail "SKILL.md not found"
fi

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]

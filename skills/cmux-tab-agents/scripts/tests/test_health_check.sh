#!/usr/bin/env bash
# Tests for ISSUE-178: health-check.sh — periodic agent health checks.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HEALTH_SH="$SCRIPTS_DIR/health-check.sh"

PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

printf '=== ISSUE-178: health-check.sh tests ===\n\n'

# T1: script exists and is executable
if [[ -x "$HEALTH_SH" ]]; then
  pass "health-check.sh exists and is executable"
else
  fail "health-check.sh not found or not executable at $HEALTH_SH"
  printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
  exit 1
fi

# T2: bash syntax check
if bash -n "$HEALTH_SH" 2>/dev/null; then
  pass "bash -n health-check.sh"
else
  fail "bash -n health-check.sh failed"
fi

# T3: --help exits 0 and prints usage
if out=$(bash "$HEALTH_SH" --help 2>&1) && printf '%s' "$out" | grep -qi 'usage'; then
  pass "--help prints usage and exits 0"
else
  fail "--help did not print usage or exited non-zero: $out"
fi

# Helper: stub git repo with worktree-like layout
make_clean_repo() {
  local d="$1"
  mkdir -p "$d/.cmux-state"
  git -C "$d" init -q -b main
  git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  printf '{"ticket":"TEST-1","phase":"implementer"}\n' > "$d/.cmux-state/dispatch.json"
}

# T4: single check on a clean worktree appends a health event with status=healthy
tmp4=$(mktemp -d)
make_clean_repo "$tmp4"
(cd "$tmp4" && bash "$HEALTH_SH" --once --no-restart 2>/dev/null) || true
pf="$tmp4/.cmux-progress.jsonl"
if [[ -f "$pf" ]] && grep -q '"kind":"health"' "$pf"; then
  pass "single --once run emits a health event"
else
  fail "expected health event in $pf; contents: $(cat "$pf" 2>/dev/null || echo MISSING)"
fi

# T5: clean worktree reports status=healthy
if grep -q '"status":"healthy"' "$pf"; then
  pass "clean worktree reports status=healthy"
else
  fail "expected status=healthy; saw: $(cat "$pf")"
fi

# T6: health event includes the three checks (process, disk, git)
if grep -q '"checks"' "$pf" && grep -q '"git"' "$pf" && grep -q '"disk"' "$pf" && grep -q '"process"' "$pf"; then
  pass "health event includes process/disk/git checks"
else
  fail "missing checks fields; saw: $(cat "$pf")"
fi

# T7: dirty git repo (uncommitted file) reports git unhealthy
tmp7=$(mktemp -d)
make_clean_repo "$tmp7"
echo dirty > "$tmp7/dirty.txt"
git -C "$tmp7" add dirty.txt
(cd "$tmp7" && bash "$HEALTH_SH" --once --no-restart 2>/dev/null) || true
pf7="$tmp7/.cmux-progress.jsonl"
# Note: "uncommitted changes" is normal mid-task, so git check should flag only corruption
# Let's instead check: corrupted .git triggers unhealthy
rm -rf "$tmp7/.git"
(cd "$tmp7" && bash "$HEALTH_SH" --once --no-restart 2>/dev/null) || true
last7=$(tail -n1 "$pf7" 2>/dev/null || echo "")
if printf '%s' "$last7" | grep -q '"git":"unhealthy"'; then
  pass "missing/corrupted .git reports git unhealthy"
else
  fail "expected git unhealthy after removing .git; got: $last7"
fi

# T8: disk check with absurd threshold (require 999PB free) flags disk unhealthy
tmp8=$(mktemp -d)
make_clean_repo "$tmp8"
(cd "$tmp8" && HEALTH_DISK_MIN_MB=999999999999 bash "$HEALTH_SH" --once --no-restart 2>/dev/null) || true
last8=$(tail -n1 "$tmp8/.cmux-progress.jsonl" 2>/dev/null || echo "")
if printf '%s' "$last8" | grep -q '"disk":"unhealthy"'; then
  pass "absurd HEALTH_DISK_MIN_MB threshold flags disk unhealthy"
else
  fail "expected disk unhealthy with huge threshold; got: $last8"
fi

# T9: overall status is "unhealthy" if any check fails
if printf '%s' "$last8" | grep -q '"status":"unhealthy"'; then
  pass "overall status=unhealthy when any check fails"
else
  fail "expected overall status=unhealthy; got: $last8"
fi

# T10: --interval flag accepted (no-op when combined with --once)
if out=$(cd "$tmp4" && bash "$HEALTH_SH" --once --interval 5 --no-restart 2>&1) && [[ $? -eq 0 || $? -eq 1 ]]; then
  pass "--interval flag accepted"
else
  fail "--interval flag rejected: $out"
fi

# T11: src tag is "health" (or has agent_role=health-checker) so consumers can filter
last11=$(tail -n1 "$tmp4/.cmux-progress.jsonl" 2>/dev/null || echo "")
if printf '%s' "$last11" | grep -qE '"agent_role":"health-checker"|"src":"health"'; then
  pass "health event tagged with health-checker role"
else
  fail "expected health-checker role tag; got: $last11"
fi

# T12: --no-restart prevents restart attempt even on unhealthy
# (already covered implicitly above; verify exit code is 0 so caller loop continues)
exit12=0
(cd "$tmp8" && HEALTH_DISK_MIN_MB=999999999999 bash "$HEALTH_SH" --once --no-restart 2>/dev/null) || exit12=$?
if [[ "$exit12" -eq 0 ]]; then
  pass "--once --no-restart exits 0 even when unhealthy"
else
  fail "--once --no-restart exited $exit12; expected 0"
fi

# T13: outputs JSON-valid event line
if command -v jq >/dev/null 2>&1; then
  if tail -n1 "$tmp4/.cmux-progress.jsonl" | jq -e . >/dev/null 2>&1; then
    pass "health event line is valid JSON"
  else
    fail "health event line is not valid JSON: $(tail -n1 "$tmp4/.cmux-progress.jsonl")"
  fi
fi

# T14: emits event with kind=health, has ts and v fields (matches progress schema)
if printf '%s' "$last11" | grep -q '"v":' && printf '%s' "$last11" | grep -q '"ts":'; then
  pass "health event has v and ts fields (matches progress schema)"
else
  fail "health event missing v/ts fields: $last11"
fi

rm -rf "$tmp4" "$tmp7" "$tmp8"

# T15: session_start hook launches background health-check loop
SS_HOOK="$(cd "$SCRIPTS_DIR/../hooks" && pwd)/session_start.sh"
STOP_HOOK="$(cd "$SCRIPTS_DIR/../hooks" && pwd)/stop.sh"
if grep -q 'health-check.sh' "$SS_HOOK"; then
  pass "session_start hook references health-check.sh"
else
  fail "session_start hook does not launch health-check.sh"
fi

# T16: stop hook reaps health-check loop
if grep -q 'health.pid' "$STOP_HOOK"; then
  pass "stop hook reaps health-check PID"
else
  fail "stop hook does not reap health-check loop"
fi

# T17: hook scripts still pass bash -n
if bash -n "$SS_HOOK" && bash -n "$STOP_HOOK"; then
  pass "session_start.sh and stop.sh pass bash -n after edits"
else
  fail "syntax error in session_start.sh or stop.sh after edits"
fi

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]

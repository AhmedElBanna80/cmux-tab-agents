#!/usr/bin/env bash
# Tests for ISSUE-93 Phase 3: agent reaction handlers (simulated dispatch loop)
#
# Validates the verdict/feedback round-trip:
#   spec-reviewer  -> ISSUES_FOUND --target implementer
#   implementer    -> feedback "ready for re-review" --target spec-reviewer
#   spec-reviewer  -> APPROVED --target implementer
#
# Tests use the real progress.sh + stream-watcher.sh together.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WATCHER_SH="$SCRIPTS_DIR/stream-watcher.sh"
PROGRESS_SH="$SCRIPTS_DIR/progress.sh"

PASS=0
FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

printf '=== ISSUE-93 Phase 3: agent reaction tests ===\n\n'

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Source watcher
# shellcheck source=/dev/null
source "$WATCHER_SH"

# ---- Scenario 1: implementer reacts to ISSUES_FOUND ----
SAW_ISSUES="$tmpdir/saw-issues"
SAW_APPROVED="$tmpdir/saw-approved"

impl_handler() {
  local event="$1"
  local verdict feedback
  verdict=$(echo "$event" | jq -r '.verdict // empty' 2>/dev/null)
  feedback=$(echo "$event" | jq -r '.feedback // empty' 2>/dev/null)
  case "$verdict" in
    ISSUES_FOUND) echo "$feedback" > "$SAW_ISSUES" ;;
    APPROVED)     echo "1"        > "$SAW_APPROVED" ;;
  esac
}
export -f impl_handler

(
  cd "$tmpdir" || exit 1
  # shellcheck source=/dev/null
  source "$WATCHER_SH"
  watch_stream implementer impl_handler --timeout 4
  WPID="$STREAM_WATCHER_PID"
  sleep 0.3

  # Reviewer reports ISSUES_FOUND
  bash "$PROGRESS_SH" --role spec-reviewer --target implementer \
    --verdict ISSUES_FOUND --feedback "Line 42 missing null check" \
    --issue-hash "hash-1" verdict 2 spec-review 2>/dev/null

  sleep 0.6

  # Reviewer later reports APPROVED
  bash "$PROGRESS_SH" --role spec-reviewer --target implementer \
    --verdict APPROVED verdict 2 spec-review 2>/dev/null

  sleep 0.8
  kill "$WPID" 2>/dev/null || true
  wait "$WPID" 2>/dev/null || true
)

if [[ -f "$SAW_ISSUES" ]] && grep -q "missing null check" "$SAW_ISSUES"; then
  pass "implementer handler captured ISSUES_FOUND feedback"
else
  fail "implementer handler did not capture ISSUES_FOUND feedback"
fi
if [[ -f "$SAW_APPROVED" ]]; then
  pass "implementer handler captured APPROVED verdict"
else
  fail "implementer handler did not capture APPROVED verdict"
fi

# ---- Scenario 2: reviewer reacts to implementer feedback ----
tmpdir2=$(mktemp -d)
trap 'rm -rf "$tmpdir" "$tmpdir2"' EXIT
SAW_FEEDBACK="$tmpdir2/saw-feedback"

reviewer_handler() {
  local event="$1"
  local feedback
  feedback=$(echo "$event" | jq -r '.feedback // empty' 2>/dev/null)
  if [[ "$feedback" == *"ready for re-review"* ]]; then
    echo "$feedback" > "$SAW_FEEDBACK"
  fi
}
export -f reviewer_handler

(
  cd "$tmpdir2" || exit 1
  # shellcheck source=/dev/null
  source "$WATCHER_SH"
  watch_stream spec-reviewer reviewer_handler --timeout 4
  WPID="$STREAM_WATCHER_PID"
  sleep 0.3

  bash "$PROGRESS_SH" --role implementer --target spec-reviewer \
    --feedback "Fixed line 42, ready for re-review" feedback 3 spec-fix-round-1 2>/dev/null

  sleep 0.8
  kill "$WPID" 2>/dev/null || true
  wait "$WPID" 2>/dev/null || true
)

if [[ -f "$SAW_FEEDBACK" ]] && grep -q "ready for re-review" "$SAW_FEEDBACK"; then
  pass "spec-reviewer handler reacts to implementer ready-for-re-review feedback"
else
  fail "spec-reviewer handler missed implementer feedback"
fi

# ---- Scenario 3: circuit-breaker — same issue_hash twice ----
tmpdir3=$(mktemp -d)
trap 'rm -rf "$tmpdir" "$tmpdir2" "$tmpdir3"' EXIT
HASH_LOG="$tmpdir3/hashes"

breaker_handler() {
  local event="$1"
  local h
  h=$(echo "$event" | jq -r '.issue_hash // empty' 2>/dev/null)
  [[ -n "$h" ]] && echo "$h" >> "$HASH_LOG"
}
export -f breaker_handler

(
  cd "$tmpdir3" || exit 1
  # shellcheck source=/dev/null
  source "$WATCHER_SH"
  watch_stream implementer breaker_handler --timeout 6
  WPID="$STREAM_WATCHER_PID"
  sleep 0.5

  bash "$PROGRESS_SH" --role spec-reviewer --target implementer \
    --verdict ISSUES_FOUND --feedback "X" --issue-hash "h-A" verdict 2 spec-review 2>/dev/null
  sleep 1.0
  bash "$PROGRESS_SH" --role spec-reviewer --target implementer \
    --verdict ISSUES_FOUND --feedback "X" --issue-hash "h-A" verdict 2 spec-review 2>/dev/null
  sleep 1.5
  kill "$WPID" 2>/dev/null || true
  wait "$WPID" 2>/dev/null || true
)

if [[ -f "$HASH_LOG" ]]; then
  count=$(wc -l < "$HASH_LOG" | tr -d ' ')
  uniq_count=$(sort -u "$HASH_LOG" | wc -l | tr -d ' ')
  if [[ "$count" -eq 2 && "$uniq_count" -eq 1 ]]; then
    pass "circuit-breaker: duplicate issue_hash detected (2 events, 1 unique)"
  else
    fail "circuit-breaker: expected count=2 uniq=1, got count=$count uniq=$uniq_count"
  fi
else
  fail "circuit-breaker: hash log not written"
fi

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]

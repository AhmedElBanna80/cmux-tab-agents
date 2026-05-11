#!/usr/bin/env bash
# test_workspace_state.sh — unit tests for workspace-state.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$SCRIPTS_DIR/workspace-state.sh"

PASS=0
FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

printf '=== workspace-state.sh unit tests ===\n\n'

if ! bash -n "$HELPER" 2>/dev/null; then
  printf 'FATAL: syntax error in %s\n' "$HELPER"
  exit 1
fi
pass "T1: bash -n workspace-state.sh"

TMPHOME=$(mktemp -d)
trap 'rm -rf "$TMPHOME"' EXIT
export HOME="$TMPHOME"
export CMUX_WORKSPACE_ID="WS-TEST-001"

# Source the helper in a subshell-safe way per test.
src() { set +u; # shellcheck source=/dev/null
source "$HELPER"; set -u; }

# T2: get_workspace_id returns $CMUX_WORKSPACE_ID
(
  src
  got=$(get_workspace_id)
  [[ "$got" == "WS-TEST-001" ]]
) && pass "T2: get_workspace_id reads CMUX_WORKSPACE_ID" \
  || fail "T2: get_workspace_id"

# T3: get_workspace_id empty when unset
(
  unset CMUX_WORKSPACE_ID
  src
  got=$(get_workspace_id)
  [[ -z "$got" ]]
) && pass "T3: get_workspace_id empty when unset" \
  || fail "T3: get_workspace_id empty"

# T4: get_state_file_path under $HOME/.claude/cmux-tab-agents/workspaces
(
  src
  got=$(get_state_file_path)
  [[ "$got" == "$HOME/.claude/cmux-tab-agents/workspaces/WS-TEST-001.json" ]]
) && pass "T4: get_state_file_path path layout" \
  || fail "T4: get_state_file_path"

# T5: init_workspace_state creates file with workspace_id and empty tickets
(
  src
  init_workspace_state
  f=$(get_state_file_path)
  [[ -f "$f" ]] && python3 -c "
import json,sys
d=json.load(open('$f'))
assert d['workspace_id']=='WS-TEST-001', d
assert d['tickets']=={}, d
"
) && pass "T5: init_workspace_state creates skeleton" \
  || fail "T5: init_workspace_state"

# T6: init is idempotent — preserves existing tickets
(
  src
  init_workspace_state
  add_surface "ISSUE-1" "implementer" "surface:10"
  init_workspace_state
  got=$(get_surface_ref "ISSUE-1" "implementer")
  [[ "$got" == "surface:10" ]]
) && pass "T6: init_workspace_state idempotent" \
  || fail "T6: init_workspace_state idempotent"

# T7: add_surface stores surface refs per ticket/phase
(
  src
  init_workspace_state
  add_surface "ISSUE-2" "implementer" "surface:20"
  add_surface "ISSUE-2" "spec-reviewer" "surface:21"
  add_surface "ISSUE-2" "code-reviewer" "surface:22"
  f=$(get_state_file_path)
  python3 -c "
import json
d=json.load(open('$f'))
s=d['tickets']['ISSUE-2']['surfaces']
assert s['implementer']=='surface:20', s
assert s['spec-reviewer']=='surface:21', s
assert s['code-reviewer']=='surface:22', s
"
) && pass "T7: add_surface stores per ticket/phase" \
  || fail "T7: add_surface"

# T8: get_ticket_surfaces returns JSON object of phase→surface
(
  src
  init_workspace_state
  add_surface "ISSUE-3" "implementer" "surface:30"
  add_surface "ISSUE-3" "spec-reviewer" "surface:31"
  got=$(get_ticket_surfaces "ISSUE-3")
  echo "$got" | python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
assert d['implementer']=='surface:30', d
assert d['spec-reviewer']=='surface:31', d
"
) && pass "T8: get_ticket_surfaces returns JSON" \
  || fail "T8: get_ticket_surfaces"

# T9: get_ticket_surfaces empty JSON for unknown ticket
(
  src
  init_workspace_state
  got=$(get_ticket_surfaces "ISSUE-NONEXIST")
  [[ "$got" == "{}" ]]
) && pass "T9: get_ticket_surfaces empty for unknown" \
  || fail "T9: get_ticket_surfaces unknown"

# T10: get_surface_ref returns specific surface; empty for missing
(
  src
  init_workspace_state
  add_surface "ISSUE-4" "implementer" "surface:40"
  got=$(get_surface_ref "ISSUE-4" "implementer")
  [[ "$got" == "surface:40" ]] || exit 1
  miss=$(get_surface_ref "ISSUE-4" "spec-reviewer")
  [[ -z "$miss" ]]
) && pass "T10: get_surface_ref hit and miss" \
  || fail "T10: get_surface_ref"

# T11: mark_ticket_done sets status=done
(
  src
  init_workspace_state
  add_surface "ISSUE-5" "implementer" "surface:50"
  mark_ticket_done "ISSUE-5"
  f=$(get_state_file_path)
  python3 -c "
import json
d=json.load(open('$f'))
assert d['tickets']['ISSUE-5']['status']=='done', d
"
) && pass "T11: mark_ticket_done sets status" \
  || fail "T11: mark_ticket_done"

# T12: remove_ticket deletes ticket entry
(
  src
  init_workspace_state
  add_surface "ISSUE-6" "implementer" "surface:60"
  remove_ticket "ISSUE-6"
  f=$(get_state_file_path)
  python3 -c "
import json
d=json.load(open('$f'))
assert 'ISSUE-6' not in d['tickets'], d
"
) && pass "T12: remove_ticket deletes entry" \
  || fail "T12: remove_ticket"

# T13: add_surface auto-inits state file if missing
(
  rm -rf "$HOME/.claude/cmux-tab-agents"
  src
  add_surface "ISSUE-7" "implementer" "surface:70"
  got=$(get_surface_ref "ISSUE-7" "implementer")
  [[ "$got" == "surface:70" ]]
) && pass "T13: add_surface auto-inits" \
  || fail "T13: add_surface auto-init"

printf '\n--- %d passed, %d failed ---\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]

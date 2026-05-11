#!/usr/bin/env bash
# Tests for Task() subagent visibility hooks:
#   pre_tool_use.sh, post_tool_use.sh (agent_id path), subagent_stop.sh
# Also smoke-tests agent-tab-renderer.sh and install-task-hooks.sh.
#
# Strategy: feed synthetic hook stdin JSON to each hook script with PATH
# containing a mock `cmux` that records invocations. Assert file side-effects
# in a temp state dir (CMUX_AGENT_STATE_DIR).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
HOOKS_DIR="$SKILL_ROOT/hooks"

PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

printf '=== task hook tests (PreToolUse / PostToolUse(agent_id) / SubagentStop) ===\n\n'

# ── shared fixtures ──────────────────────────────────────────────────────────

STATE_DIR=$(mktemp -d)
MOCK_DIR=$(mktemp -d)
trap 'rm -rf "$STATE_DIR" "$MOCK_DIR"' EXIT
export CMUX_AGENT_STATE_DIR="$STATE_DIR"

# Mock cmux: records invocations; echoes "surface:999" for new-surface calls.
CMUX_LOG=$(mktemp)
export CMUX_LOG
cat > "$MOCK_DIR/cmux" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CMUX_LOG"
case "${1:-}" in
  new-surface) echo "surface:999" ;;
esac
exit 0
MOCK
chmod +x "$MOCK_DIR/cmux"
export PATH="$MOCK_DIR:$PATH"

# ── T1: PreToolUse no-ops when agent_id is absent ────────────────────────────
: > "$CMUX_LOG"
printf '{"session_id":"sess-1","tool_name":"Read","cwd":"/tmp"}\n' \
  | "$HOOKS_DIR/pre_tool_use.sh"
if [[ ! -s "$CMUX_LOG" ]]; then
  pass "T1: PreToolUse no-ops when agent_id absent"
else
  fail "T1: PreToolUse fired cmux without agent_id; saw: $(cat "$CMUX_LOG")"
fi

# ── T2: PreToolUse spawns tab + creates JSONL for new agent_id ──────────────
: > "$CMUX_LOG"
printf '{"session_id":"sess-1","agent_id":"agent-abc","tool_name":"Read","cwd":"/tmp"}\n' \
  | "$HOOKS_DIR/pre_tool_use.sh"
if grep -q 'new-surface' "$CMUX_LOG"; then
  pass "T2a: PreToolUse calls cmux new-surface for new agent"
else
  fail "T2a: PreToolUse did not call cmux new-surface; saw: $(cat "$CMUX_LOG")"
fi
if [[ -f "$STATE_DIR/agent-abc.jsonl" ]]; then
  line=$(head -1 "$STATE_DIR/agent-abc.jsonl")
  if printf '%s' "$line" | jq -e '.agent_id == "agent-abc" and .event == "PreToolUse"' >/dev/null 2>&1; then
    pass "T2b: PreToolUse writes JSONL line with agent_id + event"
  else
    fail "T2b: JSONL line malformed: $line"
  fi
else
  fail "T2b: PreToolUse did not create per-agent JSONL"
fi
if [[ -f "$STATE_DIR/agent_tabs.json" ]]; then
  ref=$(jq -r '."agent-abc"' "$STATE_DIR/agent_tabs.json" 2>/dev/null || true)
  if [[ "$ref" == "surface:999" ]]; then
    pass "T2c: agent_tabs.json records agent_id → surface_ref"
  else
    fail "T2c: agent_tabs.json has wrong ref: $ref"
  fi
else
  fail "T2c: agent_tabs.json not created"
fi

# ── T3: PreToolUse reuses existing tab for known agent_id (no new-surface) ──
: > "$CMUX_LOG"
printf '{"session_id":"sess-1","agent_id":"agent-abc","tool_name":"Edit","cwd":"/tmp"}\n' \
  | "$HOOKS_DIR/pre_tool_use.sh"
if grep -q 'new-surface' "$CMUX_LOG"; then
  fail "T3: PreToolUse spawned duplicate tab for known agent"
else
  pass "T3: PreToolUse skips tab spawn for already-known agent"
fi
if [[ -f "$STATE_DIR/agent-abc.jsonl" ]]; then
  count=$(wc -l < "$STATE_DIR/agent-abc.jsonl")
  if [[ "$count" -ge 2 ]]; then
    pass "T3b: PreToolUse still appends JSONL line for known agent"
  else
    fail "T3b: JSONL not appended for known agent (count=$count)"
  fi
fi

# ── T4: PostToolUse appends per-agent JSONL when agent_id present ────────────
rm -f "$STATE_DIR/agent-xyz.jsonl"
printf '{"session_id":"sess-1","agent_id":"agent-xyz","tool_name":"Bash","tool_response":{"is_error":false},"cwd":"/tmp"}\n' \
  | "$HOOKS_DIR/post_tool_use.sh"
if [[ -f "$STATE_DIR/agent-xyz.jsonl" ]]; then
  line=$(head -1 "$STATE_DIR/agent-xyz.jsonl")
  if printf '%s' "$line" | jq -e '.agent_id == "agent-xyz" and .event == "PostToolUse" and .ok == true' >/dev/null 2>&1; then
    pass "T4: PostToolUse writes per-agent JSONL with agent_id + event + ok"
  else
    fail "T4: PostToolUse JSONL malformed: $line"
  fi
else
  fail "T4: PostToolUse did not create per-agent JSONL for agent-xyz"
fi

# ── T5: PostToolUse existing behaviour unaffected (worktree events) ──────────
WT_TMP=$(mktemp -d)
mkdir -p "$WT_TMP/.cmux-state"
cat > "$WT_TMP/.cmux-state/dispatch.json" <<EOF
{"ticket":"T5","phase":"implementer","started_at":"2026-01-01T00:00:00Z"}
EOF
rm -f "$WT_TMP/.cmux-events.jsonl"
printf '{"cwd":"%s","session_id":"sess-2","tool_name":"Read","tool_response":{"is_error":false}}\n' "$WT_TMP" \
  | "$HOOKS_DIR/post_tool_use.sh"
if [[ -f "$WT_TMP/.cmux-events.jsonl" ]]; then
  pass "T5: PostToolUse still writes worktree events.jsonl when no agent_id"
else
  fail "T5: PostToolUse did not write worktree events.jsonl"
fi
rm -rf "$WT_TMP"

# ── T6: SubagentStop appends FINISHED line ───────────────────────────────────
rm -f "$STATE_DIR/agent-fin.jsonl"
printf '{"session_id":"sess-1","agent_id":"agent-fin","agent_transcript_path":"/nonexistent","cwd":"/tmp"}\n' \
  | "$HOOKS_DIR/subagent_stop.sh"
if [[ -f "$STATE_DIR/agent-fin.jsonl" ]]; then
  line=$(head -1 "$STATE_DIR/agent-fin.jsonl")
  if printf '%s' "$line" | jq -e '.agent_id == "agent-fin" and .event == "SubagentStop"' >/dev/null 2>&1; then
    pass "T6: SubagentStop appends FINISHED line to per-agent JSONL"
  else
    fail "T6: SubagentStop JSONL malformed: $line"
  fi
else
  fail "T6: SubagentStop did not create per-agent JSONL"
fi

# ── T7: SubagentStop no-ops when agent_id absent ─────────────────────────────
TMP_COUNT_BEFORE=$(find "$STATE_DIR" -name "*.jsonl" | wc -l)
printf '{"session_id":"sess-1","agent_transcript_path":"/tmp/t.json","cwd":"/tmp"}\n' \
  | "$HOOKS_DIR/subagent_stop.sh"
TMP_COUNT_AFTER=$(find "$STATE_DIR" -name "*.jsonl" | wc -l)
if [[ "$TMP_COUNT_BEFORE" -eq "$TMP_COUNT_AFTER" ]]; then
  pass "T7: SubagentStop no-ops when agent_id absent"
else
  fail "T7: SubagentStop created unexpected JSONL without agent_id"
fi

# ── T8: agent-tab-renderer.sh runs on crafted JSONL ─────────────────────────
RENDERER="$SCRIPTS_DIR/agent-tab-renderer.sh"
if [[ -x "$RENDERER" ]]; then
  SAMPLE=$(mktemp)
  printf '{"ts":"2026-05-11T12:01:03Z","agent_id":"agent-abc","event":"PreToolUse","tool_name":"Read"}\n' >> "$SAMPLE"
  printf '{"ts":"2026-05-11T12:01:05Z","agent_id":"agent-abc","event":"PostToolUse","tool_name":"Read","ok":true}\n' >> "$SAMPLE"
  printf '{"ts":"2026-05-11T12:01:45Z","agent_id":"agent-abc","event":"SubagentStop","last_assistant_message":"done"}\n' >> "$SAMPLE"
  OUTPUT=$(cat "$SAMPLE" | jq -r '
    (.ts | split("T") | .[1] | split("Z") | .[0]) as $time |
    .event as $ev |
    (.tool_name // .agent_id // "") as $detail |
    if $ev == "SubagentStop" then
      "[" + $time + "] " + $ev + " " + .agent_id + "\n  Last: " + (.last_assistant_message // "")
    else
      "[" + $time + "] " + $ev + "  " + $detail
    end
  ' 2>/dev/null || true)
  if [[ -n "$OUTPUT" ]]; then
    pass "T8: agent-tab-renderer.sh jq format renders sample JSONL"
  else
    fail "T8: agent-tab-renderer.sh jq format produced empty output"
  fi
  rm -f "$SAMPLE"
else
  fail "T8: agent-tab-renderer.sh not found or not executable at $RENDERER"
fi

# ── T9: install-task-hooks.sh writes valid settings.json ─────────────────────
INSTALL="$SCRIPTS_DIR/install-task-hooks.sh"
if [[ -x "$INSTALL" ]]; then
  INSTALL_WT=$(mktemp -d)
  "$INSTALL" "$INSTALL_WT"
  SETTINGS="$INSTALL_WT/.claude/settings.json"
  if [[ -f "$SETTINGS" ]]; then
    if jq -e '.hooks.PreToolUse | length > 0' "$SETTINGS" >/dev/null 2>&1 \
       && jq -e '.hooks.PostToolUse | length > 0' "$SETTINGS" >/dev/null 2>&1 \
       && jq -e '.hooks.SubagentStop | length > 0' "$SETTINGS" >/dev/null 2>&1; then
      pass "T9a: install-task-hooks.sh writes PreToolUse + PostToolUse + SubagentStop"
    else
      fail "T9a: settings.json missing expected hook events: $(cat "$SETTINGS")"
    fi
    # Idempotency: re-running should leave same content
    "$INSTALL" "$INSTALL_WT"
    if jq -e '.hooks.PreToolUse | length > 0' "$SETTINGS" >/dev/null 2>&1; then
      pass "T9b: install-task-hooks.sh is idempotent"
    else
      fail "T9b: re-running install-task-hooks.sh broke settings.json"
    fi
  else
    fail "T9a: install-task-hooks.sh did not create settings.json"
  fi
  rm -rf "$INSTALL_WT"
else
  fail "T9: install-task-hooks.sh not found or not executable at $INSTALL"
fi

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]

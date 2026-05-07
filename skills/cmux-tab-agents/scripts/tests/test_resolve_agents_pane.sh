#!/usr/bin/env bash
# Tests for resolve-agents-pane.sh.
#
# Strategy mirrors test_hooks.sh: a mock `cmux` on PATH records every
# invocation to $CMUX_LOG and emits canned JSON / list output. Each test
# uses a fresh $HOME so the per-workspace state file is isolated.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$SCRIPTS_DIR/resolve-agents-pane.sh"

PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

printf '=== resolve-agents-pane.sh tests ===\n\n'

# Mock cmux:
#   - Logs args to $CMUX_LOG.
#   - On `list-panes`: cats $CMUX_PANES_FIXTURE if set.
#   - On `--json new-split`: emits JSON with pane_ref=$CMUX_NEW_PANE_REF.
MOCK_DIR=$(mktemp -d)
trap 'rm -rf "$MOCK_DIR" "${TEST_HOMES[@]}"' EXIT
TEST_HOMES=()

cat > "$MOCK_DIR/cmux" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CMUX_LOG"
case "$*" in
  *list-panes*)
    if [[ -n "${CMUX_PANES_FIXTURE:-}" && -f "$CMUX_PANES_FIXTURE" ]]; then
      cat "$CMUX_PANES_FIXTURE"
    fi
    exit 0
    ;;
  *new-split*)
    if [[ "${CMUX_NEW_SPLIT_FAIL:-0}" == "1" ]]; then
      echo "mock cmux: new-split forced failure" >&2
      exit 1
    fi
    printf '{"pane_ref":"%s"}\n' "${CMUX_NEW_PANE_REF:-pane:new-1}"
    exit 0
    ;;
esac
exit 0
EOF
chmod +x "$MOCK_DIR/cmux"
export PATH="$MOCK_DIR:$PATH"

new_home() {
  local h
  h=$(mktemp -d)
  TEST_HOMES+=("$h")
  printf '%s\n' "$h"
}

reset_env() {
  unset CMUX_PANES_FIXTURE CMUX_NEW_PANE_REF CMUX_NEW_SPLIT_FAIL
  CMUX_LOG=$(mktemp)
  TEST_HOMES+=("$CMUX_LOG")
  export CMUX_LOG
  : > "$CMUX_LOG"
}

# T1: Default config (no toml) → split mode → no prior state → calls new-split
# anchored on the caller surface, persists state, echoes new ref.
reset_env
HOME=$(new_home)
export HOME
export CMUX_NEW_PANE_REF="pane:created-1"
out=$("$HELPER" --caller-pane pane:planner --caller-surface surface:planner --workspace workspace:7 2>/tmp/.rap-err.t1)
state="$HOME/.claude/cmux-tab-agents/workspaces/workspace:7.json"
if [[ "$out" == "pane:created-1" ]] \
   && grep -q -- '--json new-split down' "$CMUX_LOG" \
   && grep -q -- '--surface surface:planner' "$CMUX_LOG" \
   && grep -q -- '--focus false' "$CMUX_LOG" \
   && [[ -f "$state" ]] \
   && jq -e '.agents_pane_ref == "pane:created-1"' "$state" >/dev/null 2>&1; then
  pass "default split: creates pane via cmux new-split anchored on caller surface and persists state"
else
  fail "default split: out='$out' err=$(cat /tmp/.rap-err.t1) log=$(cat "$CMUX_LOG") state=$(cat "$state" 2>/dev/null)"
fi

# T2: Split mode + prior state with valid ref → echoes existing ref, no new-split call.
reset_env
HOME=$(new_home)
export HOME
mkdir -p "$HOME/.claude/cmux-tab-agents/workspaces"
state="$HOME/.claude/cmux-tab-agents/workspaces/workspace:8.json"
printf '{"agents_pane_ref":"pane:existing","created_at":"2026-05-06T00:00:00Z"}\n' > "$state"
panes=$(mktemp)
TEST_HOMES+=("$panes")
printf 'pane:existing\npane:other\n' > "$panes"
export CMUX_PANES_FIXTURE="$panes"
out=$("$HELPER" --caller-pane pane:planner --caller-surface surface:planner --workspace workspace:8 2>/tmp/.rap-err.t2)
if [[ "$out" == "pane:existing" ]] \
   && ! grep -q -- 'new-split' "$CMUX_LOG"; then
  pass "split + valid prior state: echoes existing ref, no new-split call"
else
  fail "split + valid prior state: out='$out' err=$(cat /tmp/.rap-err.t2) log=$(cat "$CMUX_LOG")"
fi

# T3: Split mode + stale state (ref not in list-panes) → recreates, updates state.
reset_env
HOME=$(new_home)
export HOME
mkdir -p "$HOME/.claude/cmux-tab-agents/workspaces"
state="$HOME/.claude/cmux-tab-agents/workspaces/workspace:9.json"
printf '{"agents_pane_ref":"pane:stale","created_at":"2026-01-01T00:00:00Z"}\n' > "$state"
panes=$(mktemp)
TEST_HOMES+=("$panes")
printf 'pane:planner\npane:other\n' > "$panes"
export CMUX_PANES_FIXTURE="$panes"
export CMUX_NEW_PANE_REF="pane:fresh-9"
out=$("$HELPER" --caller-pane pane:planner --caller-surface surface:planner --workspace workspace:9 2>/tmp/.rap-err.t3)
if [[ "$out" == "pane:fresh-9" ]] \
   && grep -q -- 'new-split' "$CMUX_LOG" \
   && jq -e '.agents_pane_ref == "pane:fresh-9"' "$state" >/dev/null 2>&1; then
  pass "split + stale state: recreates pane via new-split and overwrites state"
else
  fail "split + stale state: out='$out' err=$(cat /tmp/.rap-err.t3) log=$(cat "$CMUX_LOG") state=$(cat "$state" 2>/dev/null)"
fi

# T4: Flat mode → echoes caller pane verbatim, no cmux new-split call,
# no state file written. --caller-surface omitted on purpose: flat mode
# does not create panes and must not require it.
reset_env
HOME=$(new_home)
export HOME
mkdir -p "$HOME/.claude"
printf 'agents_pane_layout = "flat"\n' > "$HOME/.claude/cmux-tab-agents.toml"
out=$("$HELPER" --caller-pane pane:planner --workspace workspace:10 2>/tmp/.rap-err.t4)
state="$HOME/.claude/cmux-tab-agents/workspaces/workspace:10.json"
if [[ "$out" == "pane:planner" ]] \
   && ! grep -q -- 'new-split' "$CMUX_LOG" \
   && [[ ! -f "$state" ]]; then
  pass "flat mode: echoes caller pane, no side effects"
else
  fail "flat mode: out='$out' err=$(cat /tmp/.rap-err.t4) log=$(cat "$CMUX_LOG") state_exists=$([[ -f "$state" ]] && echo y || echo n)"
fi

# T5: Custom mode + valid ref present in list-panes → echoes it.
reset_env
HOME=$(new_home)
export HOME
mkdir -p "$HOME/.claude"
cat > "$HOME/.claude/cmux-tab-agents.toml" <<EOF
agents_pane_layout = "custom"
agents_pane_ref = "pane:user-managed"
EOF
panes=$(mktemp)
TEST_HOMES+=("$panes")
printf 'pane:user-managed\npane:planner\n' > "$panes"
export CMUX_PANES_FIXTURE="$panes"
out=$("$HELPER" --caller-pane pane:planner --workspace workspace:11 2>/tmp/.rap-err.t5)
if [[ "$out" == "pane:user-managed" ]] \
   && ! grep -q -- 'new-split' "$CMUX_LOG"; then
  pass "custom mode + valid ref: echoes configured ref"
else
  fail "custom mode + valid ref: out='$out' err=$(cat /tmp/.rap-err.t5) log=$(cat "$CMUX_LOG")"
fi

# T6: Custom mode without agents_pane_ref → exits 1, message on stderr.
reset_env
HOME=$(new_home)
export HOME
mkdir -p "$HOME/.claude"
printf 'agents_pane_layout = "custom"\n' > "$HOME/.claude/cmux-tab-agents.toml"
err_file=$(mktemp)
TEST_HOMES+=("$err_file")
if "$HELPER" --caller-pane pane:planner --workspace workspace:12 >/tmp/.rap-out.t6 2>"$err_file"; then
  fail "custom missing ref: helper should exit non-zero (got 0); err=$(cat "$err_file")"
else
  if grep -qi 'agents_pane_ref' "$err_file"; then
    pass "custom mode missing ref: exits 1 with diagnostic on stderr"
  else
    fail "custom missing ref: exit OK but no useful stderr; err=$(cat "$err_file")"
  fi
fi

# T7: Custom mode with ref NOT in list-panes → exits 1.
reset_env
HOME=$(new_home)
export HOME
mkdir -p "$HOME/.claude"
cat > "$HOME/.claude/cmux-tab-agents.toml" <<EOF
agents_pane_layout = "custom"
agents_pane_ref = "pane:does-not-exist"
EOF
panes=$(mktemp)
TEST_HOMES+=("$panes")
printf 'pane:planner\n' > "$panes"
export CMUX_PANES_FIXTURE="$panes"
err_file=$(mktemp)
TEST_HOMES+=("$err_file")
if "$HELPER" --caller-pane pane:planner --workspace workspace:13 >/dev/null 2>"$err_file"; then
  fail "custom invalid ref: helper should exit non-zero; err=$(cat "$err_file")"
else
  if grep -qi 'pane:does-not-exist\|not.*found\|invalid' "$err_file"; then
    pass "custom mode + invalid ref: exits 1 with diagnostic on stderr"
  else
    fail "custom invalid ref: exit OK but stderr lacks diagnostic; err=$(cat "$err_file")"
  fi
fi

# T8: Atomic state file write — no torn writes; the file is either absent or
# valid JSON, never partial. We assert the temp file does NOT linger after a
# successful run.
reset_env
HOME=$(new_home)
export HOME
export CMUX_NEW_PANE_REF="pane:atomic-1"
"$HELPER" --caller-pane pane:planner --caller-surface surface:planner --workspace workspace:14 >/dev/null 2>/tmp/.rap-err.t8
state_dir="$HOME/.claude/cmux-tab-agents/workspaces"
leftover=$(find "$state_dir" -name '*.tmp.*' 2>/dev/null | head -1)
if [[ -z "$leftover" ]] \
   && jq -e '.agents_pane_ref' "$state_dir/workspace:14.json" >/dev/null 2>&1; then
  pass "split mode: state write is atomic (no .tmp leftovers, valid JSON)"
else
  fail "split mode: atomic write leak. leftover='$leftover' err=$(cat /tmp/.rap-err.t8)"
fi

# T9: cmux new-split failure → exit 1, no empty stdout, no state file written.
reset_env
HOME=$(new_home)
export HOME
export CMUX_NEW_SPLIT_FAIL=1
err_file=$(mktemp)
TEST_HOMES+=("$err_file")
out=$("$HELPER" --caller-pane pane:planner --caller-surface surface:planner --workspace workspace:15 2>"$err_file" || true)
state="$HOME/.claude/cmux-tab-agents/workspaces/workspace:15.json"
if [[ -z "$out" ]] && [[ ! -f "$state" ]] && [[ -s "$err_file" ]]; then
  pass "cmux new-split failure: empty stdout, no state file, stderr non-empty"
else
  fail "new-split failure: out='$out' state_exists=$([[ -f "$state" ]] && echo y || echo n) err=$(cat "$err_file")"
fi

# T10: Split mode without --caller-surface → exits 1 with diagnostic. Split
# mode anchors the new pane on a specific surface and cannot proceed without
# it.
reset_env
HOME=$(new_home)
export HOME
err_file=$(mktemp)
TEST_HOMES+=("$err_file")
if "$HELPER" --caller-pane pane:planner --workspace workspace:16 >/dev/null 2>"$err_file"; then
  fail "split missing --caller-surface: helper should exit non-zero (got 0); err=$(cat "$err_file")"
else
  if grep -qi 'caller-surface' "$err_file"; then
    pass "split mode missing --caller-surface: exits 1 with diagnostic on stderr"
  else
    fail "split missing --caller-surface: exit OK but stderr lacks diagnostic; err=$(cat "$err_file")"
  fi
fi

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]

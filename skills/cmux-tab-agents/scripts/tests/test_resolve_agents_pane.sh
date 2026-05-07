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
#   - On `--json list-panes`: cats $CMUX_PANES_JSON_FIXTURE if set, else empty.
#   - On `list-panes` (plain text): cats $CMUX_PANES_FIXTURE if set.
#   - On `--json new-split`: emits JSON with pane_ref=$CMUX_NEW_PANE_REF.
MOCK_DIR=$(mktemp -d)
trap 'rm -rf "$MOCK_DIR" "${TEST_HOMES[@]}"' EXIT
TEST_HOMES=()

cat > "$MOCK_DIR/cmux" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CMUX_LOG"
case "$*" in
  *--json*list-panes*)
    if [[ -n "${CMUX_PANES_JSON_FIXTURE:-}" && -f "$CMUX_PANES_JSON_FIXTURE" ]]; then
      cat "$CMUX_PANES_JSON_FIXTURE"
    else
      printf '{"panes":[]}\n'
    fi
    exit 0
    ;;
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
    if [[ -n "${CMUX_NEW_SPLIT_DELAY:-}" ]]; then
      sleep "$CMUX_NEW_SPLIT_DELAY"
    fi
    ref="${CMUX_NEW_PANE_REF:-pane:new-1}"
    if [[ "${CMUX_NEW_SPLIT_UNIQUE:-0}" == "1" ]]; then
      ref="$ref-$$"
    fi
    if [[ -n "${CMUX_PANES_FIXTURE:-}" ]]; then
      printf '%s\n' "$ref" >> "$CMUX_PANES_FIXTURE"
    fi
    printf '{"pane_ref":"%s"}\n' "$ref"
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
  unset CMUX_PANES_FIXTURE CMUX_PANES_JSON_FIXTURE CMUX_NEW_PANE_REF CMUX_NEW_SPLIT_FAIL
  unset CMUX_NEW_SPLIT_DELAY CMUX_NEW_SPLIT_UNIQUE
  CMUX_LOG=$(mktemp)
  TEST_HOMES+=("$CMUX_LOG")
  export CMUX_LOG
  : > "$CMUX_LOG"
}

# Helper: write a JSON list-panes fixture with two panes (planner above, neighbor below).
# Usage: write_panes_json_with_down_neighbor <out_file> <planner_ref> <neighbor_ref>
# Geometry: planner at (504, 28, 1224x706), neighbor at (504, 734, 1224x706) — bottom edge meets top.
write_panes_json_with_down_neighbor() {
  local out="$1" planner="$2" neighbor="$3"
  cat > "$out" <<JSON
{
  "panes": [
    { "ref": "$planner",  "pixel_frame": { "x": 504, "y": 28,  "width": 1224, "height": 706 } },
    { "ref": "$neighbor", "pixel_frame": { "x": 504, "y": 734, "width": 1224, "height": 706 } }
  ]
}
JSON
}

# Helper: write a JSON list-panes fixture with the planner only (no down-neighbor).
write_panes_json_solo() {
  local out="$1" planner="$2"
  cat > "$out" <<JSON
{
  "panes": [
    { "ref": "$planner", "pixel_frame": { "x": 504, "y": 28, "width": 1224, "height": 706 } }
  ]
}
JSON
}

# Helper: write a JSON list-panes fixture where the only other pane is to the side
# (not below) — same y, different x — exercises the "no down-neighbor" path even
# though there is more than one pane in the workspace.
write_panes_json_side_neighbor() {
  local out="$1" planner="$2" sibling="$3"
  cat > "$out" <<JSON
{
  "panes": [
    { "ref": "$planner",  "pixel_frame": { "x": 504,  "y": 28, "width": 1224, "height": 706 } },
    { "ref": "$sibling",  "pixel_frame": { "x": 1730, "y": 28, "width": 1224, "height": 706 } }
  ]
}
JSON
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

# T11: Split mode — down-neighbor exists, no state file → reuse the down-neighbor,
# do NOT call cmux new-split, persist neighbor ref to state file so subsequent
# runs skip the tree walk.
reset_env
HOME=$(new_home)
export HOME
panes_json=$(mktemp)
TEST_HOMES+=("$panes_json")
write_panes_json_with_down_neighbor "$panes_json" "pane:planner" "pane:below"
export CMUX_PANES_JSON_FIXTURE="$panes_json"
out=$("$HELPER" --caller-pane pane:planner --caller-surface surface:planner --workspace workspace:21 2>/tmp/.rap-err.t11)
state="$HOME/.claude/cmux-tab-agents/workspaces/workspace:21.json"
if [[ "$out" == "pane:below" ]] \
   && ! grep -q -- 'new-split' "$CMUX_LOG" \
   && [[ -f "$state" ]] \
   && jq -e '.agents_pane_ref == "pane:below"' "$state" >/dev/null 2>&1; then
  pass "split + down-neighbor exists, no state: reuses neighbor, no new-split, persists state"
else
  fail "split + down-neighbor exists, no state: out='$out' err=$(cat /tmp/.rap-err.t11) log=$(cat "$CMUX_LOG") state=$(cat "$state" 2>/dev/null)"
fi

# T12: Split mode — down-neighbor exists AND state file points at a different
# pane → cmux geometry wins (the down-neighbor is the ground truth), state is
# updated to match.
reset_env
HOME=$(new_home)
export HOME
mkdir -p "$HOME/.claude/cmux-tab-agents/workspaces"
state="$HOME/.claude/cmux-tab-agents/workspaces/workspace:22.json"
printf '{"agents_pane_ref":"pane:stale-cache","created_at":"2026-01-01T00:00:00Z"}\n' > "$state"
panes_json=$(mktemp)
TEST_HOMES+=("$panes_json")
write_panes_json_with_down_neighbor "$panes_json" "pane:planner" "pane:below"
export CMUX_PANES_JSON_FIXTURE="$panes_json"
# Plain-text list-panes also includes the stale ref so we know the resolver does
# NOT just defer to the state cache when geometry disagrees.
panes=$(mktemp)
TEST_HOMES+=("$panes")
printf 'pane:planner\npane:below\npane:stale-cache\n' > "$panes"
export CMUX_PANES_FIXTURE="$panes"
out=$("$HELPER" --caller-pane pane:planner --caller-surface surface:planner --workspace workspace:22 2>/tmp/.rap-err.t12)
if [[ "$out" == "pane:below" ]] \
   && ! grep -q -- 'new-split' "$CMUX_LOG" \
   && jq -e '.agents_pane_ref == "pane:below"' "$state" >/dev/null 2>&1; then
  pass "split + down-neighbor exists, state points elsewhere: geometry wins, state rewritten"
else
  fail "split + down-neighbor exists, state mismatch: out='$out' err=$(cat /tmp/.rap-err.t12) log=$(cat "$CMUX_LOG") state=$(cat "$state" 2>/dev/null)"
fi

# T13: Split mode — no down-neighbor (planner sits at bottom of vertical split),
# state file points at a live sibling pane (e.g. created earlier sideways) →
# resolver trusts state file, echoes that ref, no new-split.
reset_env
HOME=$(new_home)
export HOME
mkdir -p "$HOME/.claude/cmux-tab-agents/workspaces"
state="$HOME/.claude/cmux-tab-agents/workspaces/workspace:23.json"
printf '{"agents_pane_ref":"pane:sideways","created_at":"2026-01-01T00:00:00Z"}\n' > "$state"
panes_json=$(mktemp)
TEST_HOMES+=("$panes_json")
write_panes_json_side_neighbor "$panes_json" "pane:planner" "pane:sideways"
export CMUX_PANES_JSON_FIXTURE="$panes_json"
panes=$(mktemp)
TEST_HOMES+=("$panes")
printf 'pane:planner\npane:sideways\n' > "$panes"
export CMUX_PANES_FIXTURE="$panes"
out=$("$HELPER" --caller-pane pane:planner --caller-surface surface:planner --workspace workspace:23 2>/tmp/.rap-err.t13)
if [[ "$out" == "pane:sideways" ]] \
   && ! grep -q -- 'new-split' "$CMUX_LOG"; then
  pass "split + no down-neighbor + live state: vertical-split edge case, reuse state ref"
else
  fail "split + no down-neighbor + live state: out='$out' err=$(cat /tmp/.rap-err.t13) log=$(cat "$CMUX_LOG")"
fi

# T14: Split mode — no down-neighbor AND state file points at a dead pane
# (not in list-panes) → recreate via new-split, persist new ref.
reset_env
HOME=$(new_home)
export HOME
mkdir -p "$HOME/.claude/cmux-tab-agents/workspaces"
state="$HOME/.claude/cmux-tab-agents/workspaces/workspace:24.json"
printf '{"agents_pane_ref":"pane:dead","created_at":"2026-01-01T00:00:00Z"}\n' > "$state"
panes_json=$(mktemp)
TEST_HOMES+=("$panes_json")
write_panes_json_solo "$panes_json" "pane:planner"
export CMUX_PANES_JSON_FIXTURE="$panes_json"
panes=$(mktemp)
TEST_HOMES+=("$panes")
printf 'pane:planner\n' > "$panes"
export CMUX_PANES_FIXTURE="$panes"
export CMUX_NEW_PANE_REF="pane:created-24"
out=$("$HELPER" --caller-pane pane:planner --caller-surface surface:planner --workspace workspace:24 2>/tmp/.rap-err.t14)
if [[ "$out" == "pane:created-24" ]] \
   && grep -q -- 'new-split' "$CMUX_LOG" \
   && jq -e '.agents_pane_ref == "pane:created-24"' "$state" >/dev/null 2>&1; then
  pass "split + no down-neighbor + dead state: recreates via new-split, overwrites state"
else
  fail "split + no down-neighbor + dead state: out='$out' err=$(cat /tmp/.rap-err.t14) log=$(cat "$CMUX_LOG") state=$(cat "$state" 2>/dev/null)"
fi

# T15: Split mode — down-neighbor candidate has matching y but no horizontal
# overlap (e.g. a pane way to the side that happens to share a y coordinate
# from a multi-row layout) → it must NOT be picked. With no other candidates
# and no state, we fall through to new-split.
reset_env
HOME=$(new_home)
export HOME
panes_json=$(mktemp)
TEST_HOMES+=("$panes_json")
cat > "$panes_json" <<'JSON'
{
  "panes": [
    { "ref": "pane:planner",     "pixel_frame": { "x": 504,  "y": 28,  "width": 1224, "height": 706 } },
    { "ref": "pane:far-corner",  "pixel_frame": { "x": 5000, "y": 734, "width": 1224, "height": 706 } }
  ]
}
JSON
export CMUX_PANES_JSON_FIXTURE="$panes_json"
export CMUX_NEW_PANE_REF="pane:created-25"
out=$("$HELPER" --caller-pane pane:planner --caller-surface surface:planner --workspace workspace:25 2>/tmp/.rap-err.t15)
state="$HOME/.claude/cmux-tab-agents/workspaces/workspace:25.json"
if [[ "$out" == "pane:created-25" ]] \
   && grep -q -- 'new-split' "$CMUX_LOG" \
   && jq -e '.agents_pane_ref == "pane:created-25"' "$state" >/dev/null 2>&1; then
  pass "split + matching y but no horizontal overlap: rejected, falls through to new-split"
else
  fail "split + matching y but no horizontal overlap: out='$out' err=$(cat /tmp/.rap-err.t15) log=$(cat "$CMUX_LOG") state=$(cat "$state" 2>/dev/null)"
fi

# T16: Recursive dispatch — caller IS the persisted agents pane (e.g. implementer
# dispatching its reviewers from inside the agents pane). Resolver must
# short-circuit and return the same ref, WITHOUT consulting cmux geometry
# (no list-panes, no new-split). This prevents a second agents pane from being
# created next to the existing one when geometry probes race or coincidentally
# match unrelated panes.
reset_env
HOME=$(new_home)
export HOME
mkdir -p "$HOME/.claude/cmux-tab-agents/workspaces"
state="$HOME/.claude/cmux-tab-agents/workspaces/workspace:3.json"
printf '{"agents_pane_ref":"pane:27","created_at":"2026-01-01T00:00:00Z"}\n' > "$state"
out=$("$HELPER" --caller-pane pane:27 --caller-surface surface:99 --workspace workspace:3 2>/tmp/.rap-err.t16)
if [[ "$out" == "pane:27" ]] \
   && ! grep -q -- 'new-split' "$CMUX_LOG" \
   && ! grep -q -- 'list-panes' "$CMUX_LOG"; then
  pass "split + caller is persisted agents pane: short-circuit, no cmux probes"
else
  fail "split + caller is persisted agents pane: out='$out' err=$(cat /tmp/.rap-err.t16) log=$(cat "$CMUX_LOG")"
fi

# T17: Top-level dispatch unaffected (regression) — state file present with
# pane:27, but the caller is a different pane (the planner). Resolver must NOT
# short-circuit; it should fall through to the existing find_down_neighbor +
# state-file logic. With no down-neighbor and pane:27 alive in list-panes, the
# state-file fallback wins.
reset_env
HOME=$(new_home)
export HOME
mkdir -p "$HOME/.claude/cmux-tab-agents/workspaces"
state="$HOME/.claude/cmux-tab-agents/workspaces/workspace:3.json"
printf '{"agents_pane_ref":"pane:27","created_at":"2026-01-01T00:00:00Z"}\n' > "$state"
panes_json=$(mktemp)
TEST_HOMES+=("$panes_json")
write_panes_json_solo "$panes_json" "pane:5"
export CMUX_PANES_JSON_FIXTURE="$panes_json"
panes=$(mktemp)
TEST_HOMES+=("$panes")
printf 'pane:5\npane:27\n' > "$panes"
export CMUX_PANES_FIXTURE="$panes"
out=$("$HELPER" --caller-pane pane:5 --caller-surface surface:25 --workspace workspace:3 2>/tmp/.rap-err.t17)
if [[ "$out" == "pane:27" ]] \
   && ! grep -q -- 'new-split' "$CMUX_LOG" \
   && grep -q -- 'list-panes' "$CMUX_LOG"; then
  pass "split + caller is NOT persisted agents pane: existing behavior preserved"
else
  fail "split + caller is NOT persisted agents pane: out='$out' err=$(cat /tmp/.rap-err.t17) log=$(cat "$CMUX_LOG")"
fi

# T18: Concurrent dispatch — three resolvers fire against a fresh workspace at
# the same time. With the create-path locked, exactly one new-split is issued,
# all three resolvers echo the same ref, and the state file matches. Without
# the lock, each racer fires its own new-split, refs diverge, and the count
# climbs above 1.
reset_env
HOME=$(new_home)
export HOME
panes=$(mktemp)
TEST_HOMES+=("$panes")
: > "$panes"
export CMUX_PANES_FIXTURE="$panes"          # mock will append created refs here
export CMUX_NEW_PANE_REF="pane:race-18"
export CMUX_NEW_SPLIT_UNIQUE=1              # tag each new-split with mock PID
export CMUX_NEW_SPLIT_DELAY=0.5             # widen the race window
out_f1=$(mktemp); out_f2=$(mktemp); out_f3=$(mktemp)
err_f1=$(mktemp); err_f2=$(mktemp); err_f3=$(mktemp)
TEST_HOMES+=("$out_f1" "$out_f2" "$out_f3" "$err_f1" "$err_f2" "$err_f3")
"$HELPER" --caller-pane pane:planner --caller-surface surface:planner --workspace workspace:31 >"$out_f1" 2>"$err_f1" &
PID1=$!
"$HELPER" --caller-pane pane:planner --caller-surface surface:planner --workspace workspace:31 >"$out_f2" 2>"$err_f2" &
PID2=$!
"$HELPER" --caller-pane pane:planner --caller-surface surface:planner --workspace workspace:31 >"$out_f3" 2>"$err_f3" &
PID3=$!
ec1=0; ec2=0; ec3=0
wait "$PID1" || ec1=$?
wait "$PID2" || ec2=$?
wait "$PID3" || ec3=$?
out1=$(cat "$out_f1"); out2=$(cat "$out_f2"); out3=$(cat "$out_f3")
state="$HOME/.claude/cmux-tab-agents/workspaces/workspace:31.json"
new_split_count=$(grep -c -- 'new-split down' "$CMUX_LOG" || true)
if [[ "$ec1" -eq 0 ]] && [[ "$ec2" -eq 0 ]] && [[ "$ec3" -eq 0 ]] \
   && [[ -n "$out1" ]] && [[ "$out1" == "$out2" ]] && [[ "$out2" == "$out3" ]] \
   && [[ "$new_split_count" -eq 1 ]] \
   && [[ -f "$state" ]] \
   && jq -e --arg ref "$out1" '.agents_pane_ref == $ref' "$state" >/dev/null 2>&1; then
  pass "concurrent dispatches: exactly one new-split, all racers see same ref, state consistent"
else
  fail "concurrent dispatches: ec=($ec1,$ec2,$ec3) outs=($out1|$out2|$out3) new_splits=$new_split_count log=$(cat "$CMUX_LOG")"
fi

# T19: Stale lock — pre-create the lock dir to simulate a previous resolver
# that crashed without cleaning up. The new resolver must wait, then bail with
# a non-zero exit and a 'lock' diagnostic on stderr after ~5s. Without the
# lock, the resolver ignores the directory entirely and creates a pane in
# milliseconds. We allow a generous wall-clock window (4-8s) to absorb CI jitter.
reset_env
HOME=$(new_home)
export HOME
mkdir -p "$HOME/.claude/cmux-tab-agents/workspaces"
LOCK_DIR_T19="$HOME/.claude/cmux-tab-agents/workspaces/.lock.workspace:32"
mkdir "$LOCK_DIR_T19"
err_file=$(mktemp)
TEST_HOMES+=("$err_file")
start=$(date +%s)
out=$("$HELPER" --caller-pane pane:planner --caller-surface surface:planner --workspace workspace:32 2>"$err_file" || true)
end=$(date +%s)
elapsed=$((end - start))
state="$HOME/.claude/cmux-tab-agents/workspaces/workspace:32.json"
if [[ -z "$out" ]] && [[ "$elapsed" -ge 4 ]] && [[ "$elapsed" -le 8 ]] \
   && grep -qi 'lock' "$err_file" \
   && [[ ! -f "$state" ]]; then
  pass "stale lock: resolver waits ~5s, exits non-zero with lock diagnostic, no state written"
else
  fail "stale lock: out='$out' elapsed=${elapsed}s err=$(cat "$err_file") state_exists=$([[ -f "$state" ]] && echo y || echo n)"
fi

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]

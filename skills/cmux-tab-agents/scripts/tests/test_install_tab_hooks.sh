#!/usr/bin/env bash
# Tests for scripts/install-tab-hooks.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
INSTALL="$SCRIPTS_DIR/install-tab-hooks.sh"

PASS=0
FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

printf '=== install-tab-hooks tests ===\n\n'

# T1: Errors out without a worktree argument.
if "$INSTALL" 2>/dev/null; then
  fail "install-tab-hooks: should require --worktree positional"
else
  pass "install-tab-hooks errors without worktree arg"
fi

# T2: Generates a valid settings.json with all three hook events.
WT=$(mktemp -d)
"$INSTALL" "$WT" >/dev/null
SETTINGS="$WT/.claude/settings.json"
if [[ -f "$SETTINGS" ]] && jq -e '.hooks.SessionStart and .hooks.PostToolUse and .hooks.Stop' "$SETTINGS" >/dev/null 2>&1; then
  pass "install-tab-hooks generates settings.json with three hook events"
else
  fail "install-tab-hooks did not generate expected settings.json: $(cat "$SETTINGS" 2>/dev/null)"
fi

# T3: Hook commands are absolute paths to existing executables.
expected_ss="$SKILL_ROOT/hooks/session_start.sh"
got_ss=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$SETTINGS")
if [[ "$got_ss" == "$expected_ss" ]] && [[ -x "$got_ss" ]]; then
  pass "install-tab-hooks references absolute, executable session_start.sh"
else
  fail "install-tab-hooks SessionStart command wrong: $got_ss (expected $expected_ss)"
fi

# T4: Idempotent — running twice yields the same content.
A=$(jq -S . "$SETTINGS")
"$INSTALL" "$WT" >/dev/null
B=$(jq -S . "$SETTINGS")
if [[ "$A" == "$B" ]]; then
  pass "install-tab-hooks is idempotent"
else
  fail "install-tab-hooks output changed on re-run"
fi

# T5: Preserves unrelated keys in an existing settings.json.
WT2=$(mktemp -d)
mkdir -p "$WT2/.claude"
cat > "$WT2/.claude/settings.json" <<'EOF'
{
  "model": "claude-opus-4-7",
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "/bin/true" }] }]
  }
}
EOF
"$INSTALL" "$WT2" >/dev/null
SETTINGS2="$WT2/.claude/settings.json"
if jq -e '.model == "claude-opus-4-7"' "$SETTINGS2" >/dev/null \
   && jq -e '.hooks.UserPromptSubmit[0].hooks[0].command == "/bin/true"' "$SETTINGS2" >/dev/null \
   && jq -e '.hooks.Stop' "$SETTINGS2" >/dev/null; then
  pass "install-tab-hooks preserves unrelated keys + foreign hooks"
else
  fail "install-tab-hooks dropped existing keys: $(cat "$SETTINGS2")"
fi

# T6: Refuses to overwrite a malformed existing settings.json.
WT3=$(mktemp -d)
mkdir -p "$WT3/.claude"
echo "{ this is not json" > "$WT3/.claude/settings.json"
if "$INSTALL" "$WT3" 2>/dev/null; then
  fail "install-tab-hooks should refuse to overwrite invalid JSON"
else
  pass "install-tab-hooks refuses to overwrite invalid JSON"
fi

rm -rf "$WT" "$WT2" "$WT3"

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]

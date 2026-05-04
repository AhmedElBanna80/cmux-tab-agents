#!/usr/bin/env bash
# Integration test: end-to-end run of dispatch-implementer.sh with stubbed
# `cmux` and a real (temp) git repo. Verifies that the boot string sent into
# the spawned tab carries the expected --model / --effort flags resolved from
# CLI / env / per-repo TOML / user-global TOML.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCH="$SCRIPT_DIR/../dispatch-implementer.sh"
[[ -x "$DISPATCH" ]] || { echo "missing $DISPATCH" >&2; exit 1; }

PASS=0
FAIL=0

assert_contains() {
  local hay="$1" needle="$2" msg="$3"
  if [[ "$hay" == *"$needle"* ]]; then
    echo "PASS  $msg"
    PASS=$((PASS + 1))
  else
    echo "FAIL  $msg"
    echo "  haystack: $hay"
    echo "  needle:   $needle"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local hay="$1" needle="$2" msg="$3"
  if [[ "$hay" != *"$needle"* ]]; then
    echo "PASS  $msg"
    PASS=$((PASS + 1))
  else
    echo "FAIL  $msg"
    echo "  haystack: $hay"
    echo "  forbidden:$needle"
    FAIL=$((FAIL + 1))
  fi
}

# Build a sandbox: one temp dir holding the fake repo, the fake home, the
# stub cmux binary, and the captured boot string.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Fake HOME so user-global config lookup is sandboxed.
FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME/.claude"

# Stub cmux: capture every `cmux send` payload to $TMP/sent.log, fake JSON for
# `cmux --json identify` and `cmux --json new-surface`. Everything else is a
# silent no-op.
STUB_BIN="$TMP/bin"
mkdir -p "$STUB_BIN"
cat >"$STUB_BIN/cmux" <<EOF
#!/usr/bin/env bash
out_file="$TMP/sent.log"
case "\$*" in
  *"--json identify"*)
    cat <<'JSON'
{"caller":{"surface_ref":"surface:99","pane_ref":"pane:1"},"focused":{"surface_ref":"surface:99","pane_ref":"pane:1"}}
JSON
    ;;
  *"--json new-surface"*)
    echo '{"surface_ref":"surface:100"}'
    ;;
  send\\ --surface*)
    # capture the payload (last positional arg)
    last=""
    while [[ \$# -gt 0 ]]; do last="\$1"; shift; done
    printf '%s\n' "\$last" >>"\$out_file"
    ;;
  *)
    : # silent no-op for set-status / log / rename-tab / send-key / notify
    ;;
esac
exit 0
EOF
chmod +x "$STUB_BIN/cmux"

# Build a fake git repo with a .claude/cmux-tab-agents.toml.
REPO="$TMP/repo"
mkdir -p "$REPO/.claude"
git -C "$REPO" init -q
git -C "$REPO" -c user.email=t@t -c user.name=t commit --allow-empty -q -m initial
cat >"$REPO/.claude/cmux-tab-agents.toml" <<'EOF'
default_model = "from-per-repo"
default_effort = "high"
EOF

cat >"$FAKE_HOME/.claude/cmux-tab-agents.toml" <<'EOF'
default_model = "from-user-global"
default_effort = "low"
EOF

run_dispatch() {
  : >"$TMP/sent.log"
  (
    cd "$REPO"
    PATH="$STUB_BIN:$PATH" HOME="$FAKE_HOME" CMUX_WORKSPACE_ID="ws-1" \
      "$DISPATCH" \
      --ticket FOO-1 \
      --title "smoke" \
      --slug smoke \
      --task-text "noop" \
      "$@" \
      >/dev/null 2>"$TMP/dispatch.err"
  )
}

# Case 1: per-repo TOML wins when no CLI / env override.
unset CMUX_TAB_AGENTS_DEFAULT_MODEL CMUX_TAB_AGENTS_DEFAULT_EFFORT
run_dispatch
sent=$(cat "$TMP/sent.log" 2>/dev/null)
assert_contains "$sent" "--model from-per-repo" "case 1: per-repo model wins"
assert_contains "$sent" "--effort high" "case 1: per-repo effort wins"

# Case 2: env var overrides per-repo.
CMUX_TAB_AGENTS_DEFAULT_MODEL="from-env-model" \
CMUX_TAB_AGENTS_DEFAULT_EFFORT="medium" \
  run_dispatch
sent=$(cat "$TMP/sent.log")
assert_contains "$sent" "--model from-env-model" "case 2: env model wins"
assert_contains "$sent" "--effort medium"        "case 2: env effort wins"
assert_not_contains "$sent" "from-per-repo" "case 2: per-repo model not used"
unset CMUX_TAB_AGENTS_DEFAULT_MODEL CMUX_TAB_AGENTS_DEFAULT_EFFORT

# Case 3: CLI flag wins over env + per-repo.
CMUX_TAB_AGENTS_DEFAULT_MODEL="env-loser" \
  run_dispatch --model claude-opus-4-7 --effort xhigh
sent=$(cat "$TMP/sent.log")
assert_contains "$sent" "--model claude-opus-4-7" "case 3: CLI model wins"
assert_contains "$sent" "--effort xhigh"          "case 3: CLI effort wins"
assert_not_contains "$sent" "env-loser"           "case 3: env model ignored"
unset CMUX_TAB_AGENTS_DEFAULT_MODEL

# Case 4: user-global TOML used when per-repo missing.
rm -f "$REPO/.claude/cmux-tab-agents.toml"
run_dispatch
sent=$(cat "$TMP/sent.log")
assert_contains "$sent" "--model from-user-global" "case 4: user-global model used"
assert_contains "$sent" "--effort low"             "case 4: user-global effort used"

# Case 5: no config anywhere → no flags emitted.
rm -f "$FAKE_HOME/.claude/cmux-tab-agents.toml"
run_dispatch
sent=$(cat "$TMP/sent.log")
assert_not_contains "$sent" "--model"  "case 5: no model flag"
assert_not_contains "$sent" "--effort" "case 5: no effort flag"
assert_contains "$sent" "claude --dangerously-skip-permissions --append-system-prompt" \
  "case 5: backward-compat boot string"

# Case 6: invalid --effort rejected.
echo "default_model = \"x\"" >"$FAKE_HOME/.claude/cmux-tab-agents.toml"
if run_dispatch --effort wat; then
  echo "FAIL  case 6: invalid --effort should exit non-zero"
  FAIL=$((FAIL + 1))
else
  echo "PASS  case 6: invalid --effort rejected"
  PASS=$((PASS + 1))
fi

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]

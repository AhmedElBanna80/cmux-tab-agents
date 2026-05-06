#!/usr/bin/env bash
# Tests for scripts/task-adapter.sh.
#
# Strategy: stub dispatch-implementer.sh and ensure-worktree.sh on a copy of
# the scripts directory inside a tmpdir, then verify the adapter wires
# arguments through correctly, forces --planner-surface "", and emits the
# polled result file body on stdout.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

printf '=== task-adapter tests ===\n\n'

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

# Build a minimal stub scripts directory mirroring the real layout.
cp "$SCRIPTS_DIR/task-adapter.sh" "$STAGE/task-adapter.sh"
chmod +x "$STAGE/task-adapter.sh"

# Stub dispatch-implementer.sh: log args, echo a fake surface ref, exit 0.
ARGS_LOG="$STAGE/dispatch-args.log"
WT_FAKE=$(mktemp -d)
cat > "$STAGE/dispatch-implementer.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$ARGS_LOG"
echo "surface:99"
EOF
chmod +x "$STAGE/dispatch-implementer.sh"

# Stub ensure-worktree.sh: print the fake worktree path on --dry-run.
cat > "$STAGE/ensure-worktree.sh" <<EOF
#!/usr/bin/env bash
echo "$WT_FAKE"
EOF
chmod +x "$STAGE/ensure-worktree.sh"

# Stub poll-result.sh: print a canned full result body and exit 0.
cat > "$STAGE/poll-result.sh" <<'EOF'
#!/usr/bin/env bash
cat <<RESULT
---
ticket: TEST-1
phase: implementer
status: DONE
---
## Summary
adapter test body
RESULT
EOF
chmod +x "$STAGE/poll-result.sh"

# T1: Adapter forwards required args, forces --planner-surface "".
out=$("$STAGE/task-adapter.sh" implementer \
        --ticket TEST-1 --title "t" --slug s --task-text body \
        --planner-surface surface:should-be-overridden 2>/dev/null)
if grep -qx -- '--planner-surface' "$ARGS_LOG" \
   && grep -B0 -A1 -x -- '--planner-surface' "$ARGS_LOG" | tail -1 | grep -qx ''; then
  pass "task-adapter forwards --planner-surface forced to empty string"
else
  fail "task-adapter did not force --planner-surface to empty; args were: $(cat "$ARGS_LOG")"
fi

# T2: Adapter forwards --ticket / --title / --slug.
if grep -qx -- '--ticket' "$ARGS_LOG" && grep -qx 'TEST-1' "$ARGS_LOG"; then
  pass "task-adapter forwards --ticket"
else
  fail "task-adapter did not forward --ticket: $(cat "$ARGS_LOG")"
fi

# T3: Adapter prints the polled result body on stdout.
if printf '%s' "$out" | grep -q 'adapter test body' \
   && printf '%s' "$out" | grep -q '^status: DONE'; then
  pass "task-adapter prints poll-result --full body on stdout"
else
  fail "task-adapter did not emit expected body; got: $out"
fi

# T4: Adapter rejects unknown phase.
if "$STAGE/task-adapter.sh" garbage --ticket T --slug s 2>/dev/null; then
  fail "task-adapter accepted invalid phase"
else
  pass "task-adapter rejects invalid phase"
fi

# T5: Adapter requires --ticket and --slug.
if "$STAGE/task-adapter.sh" implementer --task-text x 2>/dev/null; then
  fail "task-adapter accepted missing --ticket/--slug"
else
  pass "task-adapter requires --ticket and --slug"
fi

rm -rf "$WT_FAKE"

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]

#!/usr/bin/env bash
# Test: resolved_boot_flags + claude_boot_command in _dispatch_common.sh.
# These render the trailing "--model X --effort Y" segment and the full boot
# one-liner that gets `cmux send` into the new tab.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON="$SCRIPT_DIR/../_dispatch_common.sh"
[[ -r "$COMMON" ]] || { echo "missing $COMMON" >&2; exit 1; }

PHASE="test"
# shellcheck source=../_dispatch_common.sh
source "$COMMON"
set +e

PASS=0
FAIL=0

assert_eq() {
  local got="$1" want="$2" msg="$3"
  if [[ "$got" == "$want" ]]; then
    echo "PASS  $msg"
    PASS=$((PASS + 1))
  else
    echo "FAIL  $msg"
    echo "  got:  '$got'"
    echo "  want: '$want'"
    FAIL=$((FAIL + 1))
  fi
}

# resolved_boot_flags
got=$(RESOLVED_MODEL="" RESOLVED_EFFORT="" resolved_boot_flags)
assert_eq "$got" "" "no model + no effort → empty"

got=$(RESOLVED_MODEL="claude-opus-4-7" RESOLVED_EFFORT="" resolved_boot_flags)
assert_eq "$got" " --model claude-opus-4-7" "model only"

got=$(RESOLVED_MODEL="" RESOLVED_EFFORT="high" resolved_boot_flags)
assert_eq "$got" " --effort high" "effort only"

got=$(RESOLVED_MODEL="claude-haiku-4-5-20251001" RESOLVED_EFFORT="medium" resolved_boot_flags)
assert_eq "$got" " --model claude-haiku-4-5-20251001 --effort medium" "model + effort"

# claude_boot_command — full one-liner.
got=$(RESOLVED_MODEL="" RESOLVED_EFFORT="" \
  claude_boot_command "/tmp/wt" "/tmp/wt/.cmux-tab-prompt-implementer.md")
want='cd /tmp/wt && claude --dangerously-skip-permissions --append-system-prompt "$(cat /tmp/wt/.cmux-tab-prompt-implementer.md)"'
assert_eq "$got" "$want" "boot command: no flags resolved"

got=$(RESOLVED_MODEL="claude-sonnet-4-6" RESOLVED_EFFORT="high" \
  claude_boot_command "/tmp/wt" "/tmp/wt/.cmux-tab-prompt-implementer.md")
want='cd /tmp/wt && claude --dangerously-skip-permissions --model claude-sonnet-4-6 --effort high --append-system-prompt "$(cat /tmp/wt/.cmux-tab-prompt-implementer.md)"'
assert_eq "$got" "$want" "boot command: model + effort"

got=$(RESOLVED_MODEL="" RESOLVED_EFFORT="xhigh" \
  claude_boot_command "/tmp/wt" "/tmp/wt/x.md")
want='cd /tmp/wt && claude --dangerously-skip-permissions --effort xhigh --append-system-prompt "$(cat /tmp/wt/x.md)"'
assert_eq "$got" "$want" "boot command: effort only"

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]

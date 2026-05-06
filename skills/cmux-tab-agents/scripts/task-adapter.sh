#!/usr/bin/env bash
# task-adapter.sh — sync wrapper around dispatch + poll for the planner.
#
# Replaces the chat-channel push (`cmux send` to the planner's input box)
# with a synchronous return path. The planner runs this in the background
# (Bash run_in_background=true) and waits via Monitor / poll, getting the
# result file body on stdout and the new tab's surface ref on stderr.
#
# Usage:
#   task-adapter.sh <phase> [dispatch-args...] [--timeout SECONDS]
#
# `<phase>` is implementer | spec-reviewer | code-reviewer. Remaining args
# are forwarded verbatim to the matching dispatch script, with one
# exception: `--planner-surface` is force-set to "" so any leftover
# in-prompt push is silently a no-op even if the prompt edits regress.
#
# Stdout: full result file body (poll-result.sh --full).
# Stderr: surface ref of the spawned tab (so the planner can mention it).
# Exit codes:
#   0  success
#   1  dispatch failure
#   2  poll-result.sh returned non-zero (timeout or malformed file)

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: task-adapter.sh <phase> [dispatch-args...] [--timeout SECONDS]

  phase    implementer | spec-reviewer | code-reviewer
  --timeout SECONDS  passed to poll-result.sh (default: 1800)

All other arguments are forwarded to dispatch-<phase>.sh. The
--planner-surface flag is forced to "" to disable the in-prompt push.
EOF
  exit 1
}

[[ $# -ge 1 ]] || usage
PHASE="$1"; shift

case "$PHASE" in
  implementer|spec-reviewer|code-reviewer) ;;
  -h|--help) usage ;;
  *) echo "task-adapter: invalid phase '$PHASE'" >&2; usage ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCH="$SCRIPT_DIR/dispatch-${PHASE}.sh"
POLL="$SCRIPT_DIR/poll-result.sh"
[[ -x "$DISPATCH" ]] || { echo "task-adapter: dispatch script not found: $DISPATCH" >&2; exit 1; }
[[ -x "$POLL"     ]] || { echo "task-adapter: poll-result.sh not found: $POLL" >&2; exit 1; }

# Pull --timeout out of the args, leave everything else for dispatch.
# Strip --planner-surface and its value (we force it to "").
TIMEOUT=1800
DISPATCH_ARGS=()
TICKET=""
SLUG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout)
      TIMEOUT="$2"; shift 2 ;;
    --planner-surface)
      shift 2 ;;
    --ticket)
      TICKET="$2"; DISPATCH_ARGS+=("$1" "$2"); shift 2 ;;
    --slug)
      SLUG="$2"; DISPATCH_ARGS+=("$1" "$2"); shift 2 ;;
    *)
      DISPATCH_ARGS+=("$1"); shift ;;
  esac
done

[[ -n "$TICKET" ]] || { echo "task-adapter: --ticket required" >&2; exit 1; }
[[ -n "$SLUG"   ]] || { echo "task-adapter: --slug required" >&2; exit 1; }

# Force the push channel off; the result file is the source of truth.
DISPATCH_ARGS+=(--planner-surface "")

# Dispatch — captures the spawned surface ref on stdout. Any other status
# / log output is on stderr and passes straight through.
if ! SURFACE=$("$DISPATCH" "${DISPATCH_ARGS[@]}"); then
  echo "task-adapter: dispatch-${PHASE}.sh failed" >&2
  exit 1
fi

# Echo the surface ref to stderr so the planner can refer to / focus the tab
# without us polluting stdout.
printf 'task-adapter: spawned %s at %s\n' "$PHASE" "$SURFACE" >&2

# Resolve the worktree path the dispatcher computed. ensure-worktree.sh
# is deterministic given (--ticket, --slug, --type), so we can re-invoke it
# in --dry-run mode to discover the path. Reuses the same logic that the
# dispatcher used.
ENSURE="$SCRIPT_DIR/ensure-worktree.sh"
if ! WT=$("$ENSURE" --ticket "$TICKET" --slug "$SLUG" --dry-run 2>/dev/null | tail -1); then
  echo "task-adapter: could not resolve worktree path for $TICKET/$SLUG" >&2
  exit 1
fi

# Block until the result file is written (by the agent or by the Stop hook
# safety net) and emit the full body on stdout.
if ! "$POLL" --worktree "$WT" --phase "$PHASE" --timeout "$TIMEOUT" --full; then
  echo "task-adapter: poll-result.sh exited non-zero for $WT phase=$PHASE" >&2
  exit 2
fi

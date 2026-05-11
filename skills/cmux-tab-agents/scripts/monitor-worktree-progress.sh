#!/usr/bin/env bash
# monitor-worktree-progress.sh — planner-side monitor for cmux-tab-agents progress.
#
# Tails <worktree>/.cmux-progress.jsonl, filters .kind == "done" events,
# emits one human-readable line per phase completion (implementer, spec-reviewer,
# code-reviewer), and exits when the code-reviewer's done event arrives.
#
# Designed to be invoked from the planner's Claude session via the Monitor tool:
#
#   Monitor(command="bash .../monitor-worktree-progress.sh <worktree>", until=...)
#
# Each "done" event is one stdout line so a single Monitor `until` regex can wait
# for a specific phase (e.g. 'phase=code-reviewer').
#
# Usage:
#   monitor-worktree-progress.sh <worktree-path> [--timeout SECONDS]
#   monitor-worktree-progress.sh --help

set -uo pipefail

usage() {
  cat <<'USAGE'
Usage: monitor-worktree-progress.sh <worktree-path> [--timeout SECONDS]

Tail the shared progress stream at <worktree-path>/.cmux-progress.jsonl, filter
.kind=="done" events, print one readable line per phase completion, and exit
when the code-reviewer phase completes (or after --timeout seconds).

Options:
  --timeout SECONDS   Bail out after N seconds even if code-reviewer never done.
  -h, --help          Show this help.

Output format (one line per done event):
  [HH:MM:SS] phase=<role> step=<step> name=<name>

Exit codes:
  0  code-reviewer done event observed (success)
  1  invalid args / worktree missing
  2  timeout reached before code-reviewer done
USAGE
}

WORKTREE=""
TIMEOUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --timeout) TIMEOUT="${2:-}"; shift 2 ;;
    --) shift; break ;;
    -*) printf 'monitor-worktree-progress.sh: unknown option: %s\n' "$1" >&2; usage >&2; exit 1 ;;
    *)  if [[ -z "$WORKTREE" ]]; then WORKTREE="$1"; else printf 'unexpected arg: %s\n' "$1" >&2; exit 1; fi; shift ;;
  esac
done

if [[ -z "$WORKTREE" ]]; then
  printf 'monitor-worktree-progress.sh: worktree path required\n' >&2
  usage >&2
  exit 1
fi

if [[ ! -d "$WORKTREE" ]]; then
  printf 'monitor-worktree-progress.sh: worktree not found: %s\n' "$WORKTREE" >&2
  exit 1
fi

PROGRESS_FILE="$WORKTREE/.cmux-progress.jsonl"
# Ensure file exists so tail -f can attach immediately.
touch "$PROGRESS_FILE" 2>/dev/null || {
  printf 'monitor-worktree-progress.sh: cannot create %s\n' "$PROGRESS_FILE" >&2
  exit 1
}

HAVE_JQ=0
command -v jq >/dev/null 2>&1 && HAVE_JQ=1

parse_field() {
  # parse_field <line> <field>  → echoes value or empty
  local line="$1" field="$2"
  if [[ "$HAVE_JQ" -eq 1 ]]; then
    printf '%s' "$line" | jq -r --arg f "$field" '.[$f] // empty' 2>/dev/null
  else
    printf '%s' "$line" | sed -n "s/.*\"$field\":\"\\([^\"]*\\)\".*/\\1/p"
  fi
}

emit_done() {
  local line="$1"
  local kind role step name
  kind=$(parse_field "$line" "kind")
  [[ "$kind" != "done" ]] && return 1

  role=$(parse_field "$line" "agent_role")
  [[ -z "$role" ]] && role=$(parse_field "$line" "src")
  step=$(parse_field "$line" "step")
  if [[ -z "$step" ]] && [[ "$HAVE_JQ" -eq 1 ]]; then
    step=$(printf '%s' "$line" | jq -r '.payload.step // empty' 2>/dev/null)
  fi
  name=$(parse_field "$line" "name")

  local ts
  ts=$(date '+%H:%M:%S' 2>/dev/null || printf 'now')
  printf '[%s] phase=%s step=%s name=%s\n' "$ts" "${role:-?}" "${step:-?}" "${name:-?}"

  # Terminal condition: code-reviewer phase complete.
  if [[ "$role" == "code-reviewer" ]] || [[ "$role" == "code" ]]; then
    return 0  # caller signals exit
  fi
  return 1
}

start_ts=$(date +%s)

# Start tail -f in the background so the read loop runs in *this* shell — that
# way `exit` actually exits the script rather than just the subshell on the
# right side of a pipe.
PID_FILE="$WORKTREE/.cmux-monitor.pid"
FIFO="$WORKTREE/.cmux-monitor.fifo"
rm -f "$FIFO"
mkfifo "$FIFO" 2>/dev/null || { printf 'monitor-worktree-progress.sh: cannot create fifo\n' >&2; exit 1; }

tail -n +1 -f "$PROGRESS_FILE" > "$FIFO" &
TAIL_PID=$!
echo "$TAIL_PID" > "$PID_FILE"

cleanup() {
  [[ -n "${TAIL_PID:-}" ]] && kill "$TAIL_PID" 2>/dev/null
  rm -f "$PID_FILE" "$FIFO"
}
trap cleanup EXIT INT TERM

exit_code=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue

  if [[ -n "$TIMEOUT" ]]; then
    elapsed=$(( $(date +%s) - start_ts ))
    if [[ "$elapsed" -ge "$TIMEOUT" ]]; then
      printf 'monitor-worktree-progress.sh: timeout after %ss\n' "$TIMEOUT" >&2
      exit_code=2
      break
    fi
  fi

  if emit_done "$line"; then
    exit_code=0
    break
  fi
done < "$FIFO"

exit "$exit_code"

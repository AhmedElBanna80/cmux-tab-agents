#!/usr/bin/env bash
# health-check.sh — periodic agent health checks (ISSUE-178).
#
# Runs a health check pass over the current worktree and emits a structured
# "health" event to the shared progress stream (.cmux-progress.jsonl) using
# the same plumbing established by MONITORING-116.
#
# Checks performed:
#   1. process — agent surface is responsive (cmux identify --surface alive)
#                Skipped (status="skipped") outside cmux or when --surface omitted.
#   2. disk    — worktree filesystem has at least HEALTH_DISK_MIN_MB free
#                (default: 100 MB).
#   3. git     — worktree's .git directory exists and `git status` succeeds
#                (i.e. repo is not corrupted). Uncommitted changes are NORMAL
#                mid-task and are NOT flagged unhealthy.
#
# Overall status is "healthy" iff every non-skipped check is "healthy".
#
# When a check is "unhealthy" and --no-restart is NOT set, this script will
# best-effort invoke ensure_tab_alive_or_restore (from _dispatch_common.sh)
# to attempt a crex-backed restart of a dead surface. Disk/git failures
# never trigger restart — they only emit warnings, since restart cannot
# help them.
#
# Usage:
#   health-check.sh --once [--surface REF] [--no-restart]
#   health-check.sh --interval SECONDS [--surface REF] [--no-restart]
#   health-check.sh --help
#
# Best-effort: errors are logged to stderr but never crash the caller. Exit
# code is always 0 from --once unless --strict is set.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  health-check.sh --once [--surface REF] [--no-restart] [--strict]
  health-check.sh --interval SECONDS [--surface REF] [--no-restart]

Runs a single health check pass (--once) or loops every SECONDS (--interval).
Emits a structured "health" event to .cmux-progress.jsonl in the current
directory.

Checks: process responsiveness (--surface), disk free (HEALTH_DISK_MIN_MB,
default 100), git repo integrity. Uncommitted changes are NOT flagged.

Auto-restart: if --no-restart is omitted and the process check is unhealthy,
this script invokes the existing ensure_tab_alive_or_restore helper to
attempt a crex-backed surface restore.

Env:
  HEALTH_DISK_MIN_MB   Min free MB for disk check (default 100)

Options:
  --once               Run one check and exit
  --interval SECONDS   Loop every SECONDS (default: 30)
  --surface REF        cmux surface ref to ping for process check
  --no-restart         Do not attempt restart on unhealthy process
  --strict             Exit non-zero when overall status is unhealthy (--once only)
  -h, --help           Show this help
EOF
}

MODE=""
INTERVAL=30
SURFACE=""
NO_RESTART=0
STRICT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --once)       MODE="once"; shift ;;
    --interval)   MODE="${MODE:-loop}"; INTERVAL="${2:-30}"; shift 2 ;;
    --surface)    SURFACE="${2:-}"; shift 2 ;;
    --no-restart) NO_RESTART=1; shift ;;
    --strict)     STRICT=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *)            printf 'health-check.sh: unknown arg: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

# Default to --once if neither --once nor --interval was set after parsing.
[[ -z "$MODE" ]] && MODE="once"

DISK_MIN_MB="${HEALTH_DISK_MIN_MB:-100}"

# emit_health_event <status> <process> <disk> <git> <details>
# Appends one JSONL line to .cmux-progress.jsonl matching the v2 progress
# schema, with kind="health" and agent_role="health-checker".
emit_health_event() {
  local status="$1" proc="$2" disk="$3" git_s="$4" details="$5"
  local ts sid
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || ts=""
  sid="${CLAUDE_SESSION_ID:-${SESSION_ID:-}}"
  local line=""
  if command -v jq >/dev/null 2>&1; then
    line=$(jq -cn \
      --argjson v 2 \
      --arg ts "$ts" \
      --arg sid "$sid" \
      --arg status "$status" \
      --arg proc "$proc" \
      --arg disk "$disk" \
      --arg git_s "$git_s" \
      --arg details "$details" \
      '{v:$v, ts:$ts, src:"health", sid:$sid, kind:"health",
        name:"health-check", agent_role:"health-checker",
        status:$status,
        checks:{process:$proc, disk:$disk, git:$git_s},
        payload:{status:$status, details:$details,
                 checks:{process:$proc, disk:$disk, git:$git_s}}}' 2>/dev/null) || line=""
  fi
  if [[ -z "$line" ]]; then
    # Fallback when jq is unavailable. Hand-roll JSON (status/check values
    # are constrained to a small set so quoting is safe).
    line="{\"v\":2,\"ts\":\"$ts\",\"src\":\"health\",\"sid\":\"$sid\",\"kind\":\"health\",\"name\":\"health-check\",\"agent_role\":\"health-checker\",\"status\":\"$status\",\"checks\":{\"process\":\"$proc\",\"disk\":\"$disk\",\"git\":\"$git_s\"},\"payload\":{\"status\":\"$status\",\"checks\":{\"process\":\"$proc\",\"disk\":\"$disk\",\"git\":\"$git_s\"}}}"
  fi
  printf '%s\n' "$line" >> ".cmux-progress.jsonl" 2>/dev/null || true
}

# check_process — echo "healthy" | "unhealthy" | "skipped"
check_process() {
  if [[ -z "$SURFACE" ]]; then
    printf 'skipped'
    return 0
  fi
  if ! command -v cmux >/dev/null 2>&1; then
    printf 'skipped'
    return 0
  fi
  if cmux --json identify --surface "$SURFACE" >/dev/null 2>&1; then
    printf 'healthy'
  else
    printf 'unhealthy'
  fi
}

# check_disk — echo "healthy" | "unhealthy"
check_disk() {
  # df -Pk: POSIX output in 1K blocks. Available is column 4.
  local avail_kb
  avail_kb=$(df -Pk . 2>/dev/null | awk 'NR==2 {print $4}') || avail_kb=""
  if [[ -z "$avail_kb" || ! "$avail_kb" =~ ^[0-9]+$ ]]; then
    printf 'unhealthy'
    return 0
  fi
  local avail_mb=$(( avail_kb / 1024 ))
  if [[ "$avail_mb" -lt "$DISK_MIN_MB" ]]; then
    printf 'unhealthy'
  else
    printf 'healthy'
  fi
}

# check_git — echo "healthy" | "unhealthy"
# Healthy = .git exists AND `git status` succeeds. Uncommitted changes OK.
check_git() {
  if [[ ! -d ".git" && ! -f ".git" ]]; then
    printf 'unhealthy'
    return 0
  fi
  if git status --porcelain >/dev/null 2>&1; then
    printf 'healthy'
  else
    printf 'unhealthy'
  fi
}

# try_restart — best-effort restart for unhealthy process check.
try_restart() {
  [[ "$NO_RESTART" -eq 1 ]] && return 0
  [[ -z "$SURFACE" ]] && return 0
  # Source dispatch common to reuse ensure_tab_alive_or_restore.
  # shellcheck source=/dev/null
  if [[ -r "$SCRIPT_DIR/_dispatch_common.sh" ]]; then
    # _dispatch_common.sh defines PHASE before sourcing in production use;
    # for restart-only we just need the function. Source defensively.
    PHASE="${PHASE:-implementer}" source "$SCRIPT_DIR/_dispatch_common.sh" 2>/dev/null || true
    if declare -f ensure_tab_alive_or_restore >/dev/null 2>&1; then
      ensure_tab_alive_or_restore "$PWD" "$SURFACE" >&2 || \
        printf 'health-check: restart attempt failed for surface=%s\n' "$SURFACE" >&2
    fi
  fi
}

run_once() {
  local proc disk git_s status="healthy" details=""
  proc=$(check_process)
  disk=$(check_disk)
  git_s=$(check_git)

  # Overall: any non-skipped "unhealthy" → overall unhealthy.
  for v in "$proc" "$disk" "$git_s"; do
    if [[ "$v" == "unhealthy" ]]; then
      status="unhealthy"
      break
    fi
  done

  if [[ "$status" == "unhealthy" ]]; then
    details="process=$proc disk=$disk git=$git_s disk_min_mb=$DISK_MIN_MB"
  fi

  emit_health_event "$status" "$proc" "$disk" "$git_s" "$details"

  # Only the process check can be remediated by a restart.
  if [[ "$proc" == "unhealthy" ]]; then
    try_restart
  fi

  if [[ "$status" == "unhealthy" && "$STRICT" -eq 1 ]]; then
    return 1
  fi
  return 0
}

case "$MODE" in
  once)
    run_once
    exit $?
    ;;
  loop)
    while :; do
      run_once || true
      sleep "$INTERVAL" 2>/dev/null || sleep 30
    done
    ;;
esac

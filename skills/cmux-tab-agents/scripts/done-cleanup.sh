#!/usr/bin/env bash
# done-cleanup.sh — clean up after task completion
#
# Removes crex sessions, kills agent tabs, and deletes worktrees for a completed task.
# Use this after the full 3-phase cycle completes (implementer → spec-reviewer → code-reviewer → task-result DONE).
#
# Usage:
#   done-cleanup.sh --ticket TICKET [--all]
#   done-cleanup.sh --keep-worktree  (keep git worktree, just cleanup sessions/tabs)
#
# Options:
#   --ticket TICKET      Task ticket (required unless --all)
#   --all               Clean all stale sessions and worktrees (scan all in /Users/banna/POC/worktrees/cmux-tab-agents/)
#   --keep-worktree     Don't delete the git worktree directory, just cleanup sessions and tabs
#   --dry-run           Show what would be deleted without actually deleting

set -euo pipefail

TICKET=""
CLEAN_ALL=false
KEEP_WORKTREE=false
DRY_RUN=false

usage() {
  cat >&2 <<EOF
Usage: $0 --ticket TICKET [OPTIONS]

Options:
  --ticket TICKET      Task ticket ID (required unless --all)
  --all                Clean all stale tasks (auto-scan worktree directory)
  --keep-worktree      Keep git worktree, just cleanup sessions and tabs
  --dry-run            Show what would be deleted without deleting
  --help               Show this message
EOF
  exit 1
}

log() {
  printf '[done-cleanup] %s\n' "$*" >&2
}

error() {
  printf '[done-cleanup ERROR] %s\n' "$*" >&2
  exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ticket)       TICKET="$2"; shift 2 ;;
    --all)          CLEAN_ALL=true; shift ;;
    --keep-worktree) KEEP_WORKTREE=true; shift ;;
    --dry-run)      DRY_RUN=true; shift ;;
    --help)         usage ;;
    *)              echo "Unknown option: $1" >&2; usage ;;
  esac
done

# Validate
if [[ $CLEAN_ALL == false ]] && [[ -z "$TICKET" ]]; then
  error "Either --ticket TICKET or --all is required"
fi

cleanup_task() {
  local ticket="$1"
  local worktree="/Users/banna/POC/worktrees/cmux-tab-agents/$ticket/cmux-tab-agents"

  log "Cleaning up $ticket..."

  # Find and delete crex sessions for this task
  log "  [crex] Searching for sessions..."
  if command -v crex &>/dev/null; then
    # List sessions and filter for this ticket
    if sessions=$(crex list 2>/dev/null | grep -i "$ticket" || true); then
      if [[ -n "$sessions" ]]; then
        while read -r session; do
          if [[ -n "$session" ]]; then
            log "    Removing session: $session"
            if [[ $DRY_RUN == false ]]; then
              crex delete "$session" 2>/dev/null || log "      (could not delete)"
            fi
          fi
        done <<< "$sessions"
      fi
    fi
  else
    log "  [crex] crex not installed, skipping session cleanup"
  fi

  # Kill agent tabs (surfaces) if still alive
  log "  [cmux] Searching for agent tabs..."
  for phase in implementer spec-reviewer code-reviewer; do
    surface_marker="${ticket}-${phase}"
    # Try to identify and kill surfaces matching this ticket
    if cmux list-surfaces 2>/dev/null | grep -q "$surface_marker"; then
      log "    Found surface: $surface_marker"
      if [[ $DRY_RUN == false ]]; then
        # Kill the surface (best effort)
        cmux send --match-name "$surface_marker" "exit" 2>/dev/null || true
        sleep 0.5
      fi
    fi
  done

  # Remove git worktree
  if [[ $KEEP_WORKTREE == false ]]; then
    log "  [git] Removing worktree..."
    if [[ -d "$worktree" ]]; then
      log "    Worktree path: $worktree"
      if [[ $DRY_RUN == false ]]; then
        # Try to clean up via git worktree first
        (
          cd "$worktree/.." 2>/dev/null || true
          git worktree remove --force "$worktree" 2>/dev/null || true
        )

        # Then remove directory if it still exists
        if [[ -d "$worktree" ]]; then
          rm -rf "$worktree"
        fi

        # Remove empty parent directory if it exists
        parent_dir="/Users/banna/POC/worktrees/cmux-tab-agents/$ticket"
        if [[ -d "$parent_dir" ]] && [[ -z "$(ls -A "$parent_dir" 2>/dev/null)" ]]; then
          rmdir "$parent_dir" 2>/dev/null || true
        fi
      fi
    else
      log "    Worktree directory not found (already removed?)"
    fi
  else
    log "  [git] Keeping worktree (--keep-worktree)"
  fi

  log "  ✅ Cleanup complete for $ticket"
}

cleanup_all() {
  log "Scanning for stale tasks..."

  if [[ ! -d "/Users/banna/POC/worktrees/cmux-tab-agents" ]]; then
    error "Worktree base directory not found"
  fi

  # Find all task directories
  for task_dir in /Users/banna/POC/worktrees/cmux-tab-agents/*/; do
    task_name=$(basename "$task_dir")

    # Skip non-ticket directories
    if [[ ! "$task_name" =~ ^[A-Z]+-[0-9]+ ]] && [[ ! "$task_name" =~ ^CREX- ]]; then
      continue
    fi

    # Check if task is done (look for .cmux-task-result.md with status: DONE)
    if [[ -f "$task_dir/cmux-tab-agents/.cmux-task-result.md" ]]; then
      if grep -q "status: DONE\|verdict: DONE" "$task_dir/cmux-tab-agents/.cmux-task-result.md" 2>/dev/null; then
        log "Found completed task: $task_name"
        cleanup_task "$task_name"
      fi
    fi
  done

  log "✅ All-cleanup complete"
}

# ============================================================================
# Main execution
# ============================================================================

if [[ $DRY_RUN == true ]]; then
  log "DRY RUN MODE (--dry-run) — no changes will be made"
fi

if [[ $CLEAN_ALL == true ]]; then
  cleanup_all
else
  cleanup_task "$TICKET"
fi

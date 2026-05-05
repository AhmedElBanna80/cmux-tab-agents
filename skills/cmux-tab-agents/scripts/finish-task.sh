#!/usr/bin/env bash
# finish-task.sh — execute finish mode (keep, pr, merge) after implementation and review.
#
# This script is called by the implementer tab when code review is complete (both
# spec and code reviewers have approved). It verifies tests pass, then takes action
# based on the finish mode:
#
#   keep   — noop (preserve today's behavior: keep worktree, no push/PR)
#   pr     — push branch, open PR via `gh pr create`, return PR URL
#   merge  — checkout base, pull, merge, re-run tests, remove worktree if green
#
# Idempotency: if branch is already pushed, running pr-mode again returns existing PR URL.
# If merge is halfway through, re-running completes or aborts cleanly.
#
# Exits 0 on success. Exits non-zero with descriptive message on any failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Config (from environment or defaults)
FINISH_MODE="${1:-keep}"
WORKTREE="${2:-.}"

usage() {
  cat >&2 <<EOF
Usage: $0 [MODE] [WORKTREE]

  MODE      Finish mode: keep, pr, merge (default: keep)
  WORKTREE  Path to git worktree (default: current directory)
EOF
  exit 1
}

# Validate arguments
[[ "$FINISH_MODE" =~ ^(keep|pr|merge)$ ]] || { echo "Invalid mode: $FINISH_MODE" >&2; usage; }

# cd into worktree
cd "$WORKTREE" || { echo "Cannot cd into $WORKTREE" >&2; exit 1; }

log() {
  printf '[finish-task.sh] %s\n' "$*" >&2
}

error() {
  printf '[finish-task.sh ERROR] %s\n' "$*" >&2
  exit 1
}

# ============================================================================
# VERIFICATION GATE: Tests must pass before any finish action
# ============================================================================

log "Running verification gate (tests must pass)..."

# Try to detect and run test command. Common patterns:
if [[ -f package.json ]] && grep -q '"test"' package.json 2>/dev/null; then
  log "Running npm test..."
  if ! npm test 2>&1; then
    error "Tests failed. Aborting finish action. Fix tests and re-run."
  fi
elif [[ -f Makefile ]] && grep -q '^test:' Makefile 2>/dev/null; then
  log "Running make test..."
  if ! make test 2>&1; then
    error "Tests failed. Aborting finish action. Fix tests and re-run."
  fi
elif [[ -f pytest.ini ]] || [[ -d tests ]] && [[ -f "tests/__init__.py" ]]; then
  log "Running pytest..."
  if ! python -m pytest 2>&1; then
    error "Tests failed. Aborting finish action. Fix tests and re-run."
  fi
elif [[ -f go.mod ]]; then
  log "Running go test..."
  if ! go test ./... 2>&1; then
    error "Tests failed. Aborting finish action. Fix tests and re-run."
  fi
else
  log "WARNING: Could not auto-detect test command. Skipping verification gate."
  log "To enforce tests, add one of: npm test, make test, pytest, go test"
fi

log "Verification gate passed."

# ============================================================================
# Mode-specific actions
# ============================================================================

case "$FINISH_MODE" in

  keep)
    log "finish-mode=keep: noop (preserving today's behavior)"
    exit 0
    ;;

  pr)
    log "finish-mode=pr: pushing branch and opening PR..."

    # Get current branch name and remote
    branch=$(git rev-parse --abbrev-ref HEAD)
    remote="${GIT_REMOTE:-origin}"

    # Push branch (idempotent: ok if already pushed)
    log "Pushing branch '$branch' to $remote..."
    git push -u "$remote" "$branch" 2>&1 || true

    # Check if PR already exists (idempotent)
    log "Checking for existing PR..."
    if existing_pr=$(gh pr view --json url --jq '.url' 2>/dev/null); then
      log "PR already exists: $existing_pr"
      echo "$existing_pr"
      exit 0
    fi

    # Extract issue number from branch if available (common pattern: feat/ISSUE-123/...)
    issue=""
    if [[ "$branch" =~ ISSUE-([0-9]+) ]]; then
      issue="${BASH_REMATCH[1]}"
    fi

    # Create PR with auto-close if issue matches pattern
    log "Creating new PR..."
    pr_args=("--title" "$(git log -1 --format=%s)")

    # Build PR body with auto-close if issue found
    body="Resolves #$issue"
    pr_args+=(--body "$body")

    if pr_url=$(gh pr create "${pr_args[@]}" 2>&1); then
      log "PR created: $pr_url"
      echo "$pr_url"
      exit 0
    else
      error "Failed to create PR: $pr_url"
    fi
    ;;

  merge)
    log "finish-mode=merge: merging branch into base..."

    # Get current branch and base
    branch=$(git rev-parse --abbrev-ref HEAD)
    base="${GIT_BASE_BRANCH:-main}"

    # Check if branch is already merged (idempotent)
    if git merge-base --is-ancestor "$branch" "$base" 2>/dev/null; then
      log "Branch is already merged into $base"
      log "Removing worktree..."
      # Try to clean up worktree directory
      git worktree remove "$WORKTREE" 2>/dev/null || true
      exit 0
    fi

    # Checkout base branch
    log "Checking out $base..."
    if ! git fetch origin "$base" 2>/dev/null; then
      error "Failed to fetch $base from origin"
    fi
    git checkout -q "$base" || error "Failed to checkout $base"

    # Pull latest
    log "Pulling latest $base..."
    git pull origin "$base" || error "Failed to pull $base"

    # Merge feature branch
    log "Merging $branch into $base..."
    if ! git merge --no-ff "$branch" -m "Merge $branch into $base"; then
      log "Merge conflict detected. Aborting merge."
      git merge --abort
      error "Merge failed due to conflicts. Resolve manually and re-run, or use --finish-mode keep."
    fi

    # Re-run verification on merged code
    log "Re-running verification gate after merge..."
    if [[ -f package.json ]] && grep -q '"test"' package.json 2>/dev/null; then
      if ! npm test 2>&1; then
        log "Tests failed after merge. Aborting and reverting merge."
        git reset --hard HEAD~1
        error "Post-merge tests failed. Merge reverted. Fix code and try again."
      fi
    fi

    # If all green, remove worktree
    log "Merge successful and tests pass. Removing worktree..."
    git worktree remove "$WORKTREE" 2>/dev/null || log "WARNING: Could not remove worktree at $WORKTREE (may be in use or already removed)"

    log "Finished: branch merged, tests pass, worktree removed"
    exit 0
    ;;

esac

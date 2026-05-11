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
# shellcheck source=./workspace-state.sh
source "$SCRIPT_DIR/workspace-state.sh"

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

run_tests() {
  if [[ -f package.json ]] && grep -q '"test"' package.json 2>/dev/null; then
    log "Running npm test..."
    npm test 2>&1
  elif [[ -f Makefile ]] && grep -q '^test:' Makefile 2>/dev/null; then
    log "Running make test..."
    make test 2>&1
  elif [[ -f pytest.ini ]] || [[ -d tests ]] && [[ -f "tests/__init__.py" ]]; then
    log "Running pytest..."
    python -m pytest 2>&1
  elif [[ -f go.mod ]]; then
    log "Running go test..."
    go test ./... 2>&1
  else
    log "WARNING: Could not auto-detect test command. Skipping test execution."
    log "To enforce tests, add one of: npm test, make test, pytest, go test"
    return 0
  fi
}

# ============================================================================
# VERIFICATION GATE: Tests must pass before any finish action
# ============================================================================

log "Running verification gate (tests must pass)..."

if ! run_tests; then
  error "Tests failed. Aborting finish action. Fix tests and re-run."
fi

log "Verification gate passed."

# ============================================================================
# Cleanup manifest: read ticket from dispatch.json, look up surfaces from
# workspace state, write .cmux-cleanup-manifest.json so the planner can offer
# auto-cleanup once both reviewers have approved.
# ============================================================================

bash "$SCRIPT_DIR/progress.sh" --role implementer started 2 finish-cleanup-manifest 2>/dev/null || true

TICKET=""
DISPATCH_JSON="$WORKTREE/.cmux-state/dispatch.json"
if [[ -f "$DISPATCH_JSON" ]]; then
  TICKET=$(python3 -c "import json,sys
try:
    print(json.load(open('$DISPATCH_JSON')).get('ticket',''))
except Exception:
    print('')" 2>/dev/null || true)
fi

if [[ -n "$TICKET" ]]; then
  SURFACES_JSON=$(get_ticket_surfaces "$TICKET" 2>/dev/null || echo '{}')
  MANIFEST="$WORKTREE/.cmux-cleanup-manifest.json"
  TICKET="$TICKET" WT="$WORKTREE" MODE="$FINISH_MODE" \
    SURFACES="$SURFACES_JSON" MPATH="$MANIFEST" \
    python3 - <<'PY' || log "WARNING: could not write cleanup manifest"
import json, os, time
manifest = {
    "v": 1,
    "ticket": os.environ["TICKET"],
    "worktree": os.environ["WT"],
    "finish_mode": os.environ["MODE"],
    "surfaces": json.loads(os.environ.get("SURFACES") or "{}"),
    "written_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
}
path = os.environ["MPATH"]
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, indent=2)
    fh.write("\n")
os.replace(tmp, path)
PY
  log "Wrote cleanup manifest: $MANIFEST"
else
  log "Skipping cleanup manifest: no ticket in $DISPATCH_JSON"
fi

bash "$SCRIPT_DIR/progress.sh" --role implementer "done" 2 finish-cleanup-manifest 2>/dev/null || true

# ============================================================================
# Mode-specific actions
# ============================================================================

case "$FINISH_MODE" in

  keep)
    log "finish-mode=keep: noop (preserving worktree and branch)"
    # Explicitly verify worktree still exists (guard against accidental deletion)
    if [ ! -d "$WORKTREE" ]; then
      log "WARNING: Worktree directory was deleted. This should not happen in keep mode."
      log "Attempting to recreate worktree from current branch..."
      PARENT_DIR="$(dirname "$WORKTREE")"
      mkdir -p "$PARENT_DIR"
      if git worktree add "$WORKTREE" --detach HEAD 2>/dev/null; then
        log "Worktree recreated successfully at $WORKTREE"
      else
        log "WARNING: Could not recreate worktree. It may have been cleaned up by git."
      fi
    fi
    exit 0
    ;;

  pr)
    log "finish-mode=pr: pushing branch and opening PR..."

    # Get current branch name and remote
    branch=$(git rev-parse --abbrev-ref HEAD)
    remote="${GIT_REMOTE:-origin}"

    # Push branch (idempotent: ok if already pushed)
    log "Pushing branch '$branch' to $remote..."
    if ! git push -u "$remote" "$branch" 2>&1; then
      log "WARNING: Failed to push branch. Check git auth and network connectivity."
    fi

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

    # Build PR body with auto-close if issue found (no auto-close for non-ISSUE branches)
    if [[ -n "$issue" ]]; then
      body="Resolves #$issue"
      pr_args+=(--body "$body")
    fi

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
    if ! run_tests; then
      log "Tests failed after merge. Aborting and reverting merge."
      git reset --hard HEAD~1
      error "Post-merge tests failed. Merge reverted. Fix code and try again."
    fi

    # If all green, remove worktree
    log "Merge successful and tests pass. Removing worktree..."
    git worktree remove "$WORKTREE" 2>/dev/null || log "WARNING: Could not remove worktree at $WORKTREE (may be in use or already removed)"

    log "Finished: branch merged, tests pass, worktree removed"
    exit 0
    ;;

esac

#!/usr/bin/env bash
# ensure-worktree.sh — idempotent, repo-agnostic worktree provisioning
# for the cmux-tab-agents skill.
#
# Usage:
#   ensure-worktree.sh --ticket TICKET --slug SLUG [--type feat|fix|...] [--dry-run]
#
# Stdout: absolute path to the worktree on success.
# Exit codes:
#   0 = worktree exists or was created (resume or fresh)
#   1 = caller error or unrecoverable state (e.g. stale dir, no repo)

set -euo pipefail

TICKET=""
SLUG=""
TYPE=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ticket)   TICKET="$2"; shift 2 ;;
    --slug)     SLUG="$2"; shift 2 ;;
    --type)     TYPE="$2"; shift 2 ;;
    --dry-run)  DRY_RUN=1; shift ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# //;s/^#//'
      exit 0
      ;;
    *) echo "ensure-worktree: unknown arg '$1'" >&2; exit 1 ;;
  esac
done

[[ -z "$TICKET" ]] && { echo "ensure-worktree: --ticket required" >&2; exit 1; }
[[ -z "$SLUG"   ]] && { echo "ensure-worktree: --slug required"   >&2; exit 1; }

# 1. Discover the parent repo
if ! REPO=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null); then
  echo "ensure-worktree: not inside a git repo (PWD=$PWD)" >&2
  exit 1
fi
REPO_NAME=$(basename "$REPO")

# Default branch — try origin/HEAD, fall back to main, then master.
DEFAULT_BRANCH=""
if ref=$(git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null); then
  DEFAULT_BRANCH="${ref#refs/remotes/origin/}"
elif git -C "$REPO" show-ref --verify --quiet refs/heads/main; then
  DEFAULT_BRANCH="main"
elif git -C "$REPO" show-ref --verify --quiet refs/heads/master; then
  DEFAULT_BRANCH="master"
else
  echo "ensure-worktree: cannot determine default branch in $REPO" >&2
  exit 1
fi

# 2. Discover the worktree base directory
CONFIG_FILE="$REPO/.claude/cmux-tab-agents.toml"
read_config_value() {
  local key="$1"
  [[ -f "$CONFIG_FILE" ]] || return 1
  # naive TOML grep — sufficient for flat key-value config
  grep -E "^[[:space:]]*${key}[[:space:]]*=" "$CONFIG_FILE" 2>/dev/null \
    | head -1 \
    | sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//" \
    | sed -E 's/^"(.*)"$/\1/' \
    | sed -E "s/^'(.*)'\$/\1/"
}

BASE=""
if [[ -n "${CMUX_TAB_AGENTS_WORKTREE_BASE:-}" ]]; then
  BASE="$CMUX_TAB_AGENTS_WORKTREE_BASE/$REPO_NAME"
elif cfg_base=$(read_config_value "worktree_base"); [[ -n "$cfg_base" ]]; then
  if [[ "$cfg_base" = /* ]]; then
    BASE="$cfg_base"
  else
    BASE="$REPO/$cfg_base"
  fi
elif [[ -d "$REPO/.worktrees" ]] && \
     git -C "$REPO" check-ignore -q .worktrees 2>/dev/null; then
  BASE="$REPO/.worktrees"
else
  # sibling default — matches the alpheya layout
  BASE="$(dirname "$REPO")/worktrees/$REPO_NAME"
fi

# Resolve type default from config if not on cli
if [[ -z "$TYPE" ]]; then
  if cfg_type=$(read_config_value "branch_type_default"); [[ -n "$cfg_type" ]]; then
    TYPE="$cfg_type"
  else
    TYPE="feat"
  fi
fi

# Optional ticket pattern check
if cfg_pattern=$(read_config_value "ticket_pattern"); [[ -n "$cfg_pattern" ]]; then
  if ! [[ "$TICKET" =~ $cfg_pattern ]]; then
    echo "ensure-worktree: ticket '$TICKET' does not match pattern '$cfg_pattern'" >&2
    exit 1
  fi
fi

# 3. Compute target path
WT="$BASE/$TICKET/$REPO_NAME"
BRANCH="$TYPE/$TICKET/$SLUG"

if [[ "$DRY_RUN" -eq 1 ]]; then
  cat >&2 <<EOF
ensure-worktree (dry-run):
  repo:           $REPO
  default branch: $DEFAULT_BRANCH
  base:           $BASE
  worktree:       $WT
  branch:         $BRANCH
EOF
  echo "$WT"
  exit 0
fi

# 4. Resume vs create vs stale
if [[ -e "$WT" ]]; then
  if git -C "$WT" rev-parse --git-dir >/dev/null 2>&1; then
    # resume
    echo "$WT"
    exit 0
  else
    cat >&2 <<EOF
ensure-worktree: '$WT' exists but is not a git worktree.
Please remove or rename it before retrying. Refusing to clobber unknown content.
EOF
    exit 1
  fi
fi

mkdir -p "$(dirname "$WT")"

# Check if a worktree already exists for this ticket (prevent nested worktrees)
# This avoids creating nested structures when spec-reviewer/code-reviewer is dispatched
# in the same TICKET directory after implementer has already created the worktree
EXISTING_WT=""
while IFS= read -r -u 3 line; do
  # git worktree list format: /path/to/worktree branch [detached]
  if [[ "$line" =~ ^([^ ]+)[[:space:]] ]]; then
    existing_path="${BASH_REMATCH[1]}"
    # Check if this worktree is for the same TICKET
    if [[ "$existing_path" == *"/$TICKET/cmux-tab-agents" ]]; then
      EXISTING_WT="$existing_path"
      break
    fi
  fi
done 3< <(git -C "$REPO" worktree list)

if [[ -n "$EXISTING_WT" ]]; then
  echo "Reusing existing worktree: $EXISTING_WT" >&2
  WT="$EXISTING_WT"
  echo "$WT"
  exit 0
fi

# Fetch origin/main to ensure fresh base (not stale local main)
git -C "$REPO" fetch origin main --quiet 2>/dev/null || true

# Reuse branch if it already exists; otherwise create it off origin/main.
if git -C "$REPO" show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git -C "$REPO" worktree add "$WT" "$BRANCH" >&2
else
  git -C "$REPO" worktree add "$WT" -b "$BRANCH" origin/main >&2
fi

# 5. Best-effort project bootstrap
bootstrap() {
  local log="$WT/.cmux-bootstrap.log"
  : > "$log"

  run() {
    echo ">>> $*" | tee -a "$log" >&2
    if "$@" >>"$log" 2>&1; then
      echo "    ok" >&2
    else
      echo "    warning: command failed (continuing)" >&2
    fi
  }

  cd "$WT"

  # Override hatch
  if cfg_setup=$(read_config_value "setup_command"); [[ -n "$cfg_setup" ]]; then
    run bash -c "$cfg_setup"
    return 0
  fi

  if [[ -f mise.toml || -f .mise.toml ]] && command -v mise >/dev/null 2>&1; then
    run mise install
  fi

  if [[ -f package.json ]]; then
    if [[ -f pnpm-lock.yaml ]] && command -v pnpm >/dev/null 2>&1; then
      run pnpm install --frozen-lockfile
    elif [[ -f bun.lockb || -f bun.lock ]] && command -v bun >/dev/null 2>&1; then
      run bun install --frozen-lockfile
    elif [[ -f yarn.lock ]] && command -v yarn >/dev/null 2>&1; then
      run yarn install --frozen-lockfile
    elif [[ -f package-lock.json ]] && command -v npm >/dev/null 2>&1; then
      run npm ci
    elif command -v npm >/dev/null 2>&1; then
      run npm install
    fi
  fi

  if [[ -f pyproject.toml ]]; then
    if [[ -f uv.lock ]] && command -v uv >/dev/null 2>&1; then
      run uv sync
    elif command -v pip >/dev/null 2>&1; then
      run pip install -e .
    fi
  fi

  if [[ -f Gemfile ]] && command -v bundle >/dev/null 2>&1; then
    run bundle install
  fi

  if [[ -f go.mod ]] && command -v go >/dev/null 2>&1; then
    run go mod download
  fi

  return 0
}

bootstrap || true

echo "$WT"

#!/usr/bin/env bash
# dev-unlink.sh — reverse dev-link.sh.
#
# Removes <prefix>/skills/cmux-tab-agents and <prefix>/commands/cmux-tab-agents
# IFF each is a symlink whose target lives inside the cmux-tab-agents repo.
# Real directories are never deleted; unrelated symlinks are left in place.
#
# Usage:
#   ./scripts/dev-unlink.sh                # uses $HOME/.claude as prefix,
#                                          # repo = git rev-parse from PWD
#   ./scripts/dev-unlink.sh --prefix DIR   # sandbox (used by tests)
#   ./scripts/dev-unlink.sh --repo PATH    # treat PATH as the repo root

set -euo pipefail

PREFIX="$HOME/.claude"
REPO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --repo)   REPO="$2";   shift 2 ;;
    -h|--help)
      sed -n '2,13p' "$0" | sed 's/^# //;s/^#//'
      exit 0
      ;;
    *) echo "dev-unlink: unknown arg '$1'" >&2; exit 1 ;;
  esac
done

if [[ -z "$REPO" ]]; then
  REPO=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null) || REPO=""
fi
if [[ -n "$REPO" ]]; then
  REPO=$(cd "$REPO" 2>/dev/null && pwd) || REPO=""
fi

# is_ours <symlink_target>: 0 if the target lives inside $REPO (or, when REPO
# is unknown, has the cmux-tab-agents fingerprint).
is_ours() {
  local target="$1"
  if [[ -n "$REPO" ]]; then
    [[ "$target" == "$REPO"/* ]]
    return $?
  fi
  # Fallback: target path mentions cmux-tab-agents OR ends in
  # /skills/cmux-tab-agents (the canonical link target).
  [[ "$target" == *"cmux-tab-agents"* || "$target" == */skills/cmux-tab-agents ]]
}

remove_if_ours() {
  local link="$1"
  if [[ ! -e "$link" && ! -L "$link" ]]; then
    return 0
  fi
  if [[ ! -L "$link" ]]; then
    echo "i $link is a real path — leaving alone (use 'rm -rf' yourself if you mean to)."
    return 0
  fi
  local target
  target=$(readlink "$link")
  if ! is_ours "$target"; then
    echo "i $link → $target  (not ours; leaving alone)"
    return 0
  fi
  rm "$link"
  echo "- $link  (was → $target)"
}

remove_if_ours "$PREFIX/skills/cmux-tab-agents"
remove_if_ours "$PREFIX/commands/cmux-tab-agents"

echo
echo "Dev-unlinked. The user-scope plugin tree no longer points at this worktree."

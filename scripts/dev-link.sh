#!/usr/bin/env bash
# dev-link.sh — wire the working repo into Claude Code's user-scope plugin tree
# via symlinks, so edits land live without re-installing the plugin.
#
# Idempotent. Refuses to clobber a real directory unless --force.
#
# Usage:
#   ./scripts/dev-link.sh                  # uses $HOME/.claude as prefix
#   ./scripts/dev-link.sh --force          # replace any real dirs in the way
#   ./scripts/dev-link.sh --prefix DIR     # sandbox (used by tests)
#   ./scripts/dev-link.sh --repo PATH      # treat PATH as the repo root
#                                          # (defaults to git rev-parse from PWD)
#
# What it links:
#   <prefix>/skills/cmux-tab-agents   → <repo>/skills/cmux-tab-agents
#   <prefix>/commands/cmux-tab-agents → <repo>/commands           (if exists)
#
# Pair with dev-unlink.sh to reverse.

set -euo pipefail

PREFIX="$HOME/.claude"
REPO=""
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --repo)   REPO="$2";   shift 2 ;;
    --force)  FORCE=1;     shift ;;
    -h|--help)
      sed -n '2,17p' "$0" | sed 's/^# //;s/^#//'
      exit 0
      ;;
    *) echo "dev-link: unknown arg '$1'" >&2; exit 1 ;;
  esac
done

if [[ -z "$REPO" ]]; then
  REPO=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null) || {
    echo "dev-link: not inside a git repo. Pass --repo PATH explicitly." >&2
    exit 1
  }
else
  if ! git -C "$REPO" rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "dev-link: --repo '$REPO' is not a git repo." >&2
    exit 1
  fi
  REPO=$(cd "$REPO" && pwd)
fi

if [[ ! -d "$REPO/skills/cmux-tab-agents" ]]; then
  echo "dev-link: '$REPO' does not contain skills/cmux-tab-agents." >&2
  echo "         Are you sure this is the cmux-tab-agents repo?" >&2
  exit 1
fi

# install_link <link_path> <target_path>
# - if link is already the right symlink: no-op
# - if link is some other symlink: replace
# - if link is a real file/dir: refuse unless --force
# - else: create
install_link() {
  local link="$1" target="$2"
  mkdir -p "$(dirname "$link")"
  if [[ -L "$link" ]]; then
    local cur
    cur=$(readlink "$link")
    if [[ "$cur" == "$target" ]]; then
      echo "= $link → $target  (already correct)"
      return 0
    fi
    rm "$link"
    ln -s "$target" "$link"
    echo "↻ $link → $target  (was → $cur)"
    return 0
  fi
  if [[ -e "$link" ]]; then
    if [[ "$FORCE" -ne 1 ]]; then
      echo "dev-link: refusing to clobber real path '$link' — pass --force to replace." >&2
      return 1
    fi
    rm -rf "$link"
    ln -s "$target" "$link"
    echo "✗→✓ $link → $target  (replaced real dir; --force)"
    return 0
  fi
  ln -s "$target" "$link"
  echo "+ $link → $target"
}

rc=0
install_link "$PREFIX/skills/cmux-tab-agents" "$REPO/skills/cmux-tab-agents" || rc=1

if [[ -d "$REPO/commands" ]]; then
  install_link "$PREFIX/commands/cmux-tab-agents" "$REPO/commands" || rc=1
else
  echo "i $REPO/commands missing — skip commands link (will work after v0.3.0)"
fi

if [[ "$rc" -ne 0 ]]; then
  exit 1
fi

cat <<EOF

Dev-linked. The plugin now loads directly from your worktree.
Daily loop:  edit → /reload-plugins in Claude Code → test.
Reverse:     ./scripts/dev-unlink.sh
EOF

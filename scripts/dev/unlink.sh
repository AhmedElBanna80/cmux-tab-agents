#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_target-path.sh
source "${script_dir}/_target-path.sh"

repo_root=$(git rev-parse --show-toplevel)
target=$(compute_target_path)

if [[ ! -e "$target" && ! -L "$target" ]]; then
  echo "not linked"
  exit 0
fi

if [[ -L "$target" ]]; then
  current=$(resolve_symlink_target "$target")
  if [[ "$current" != "$repo_root" ]]; then
    echo "warning: target is a symlink to '${current}', not this repo (${repo_root}); refusing to remove" >&2
    exit 1
  fi
  rm "$target"
  echo "unlinked: $target"

  parent_dir=$(dirname "$target")
  base=$(basename "$target")
  shopt -s nullglob
  backups=( "$parent_dir/$base".bak-* )
  shopt -u nullglob
  if [[ ${#backups[@]} -gt 0 ]]; then
    echo "found backup(s) — restore manually if you want the previous install:"
    for b in "${backups[@]}"; do
      echo "  mv \"$b\" \"$target\""
    done
  fi
  exit 0
fi

echo "target is not a symlink, refusing to remove: $target" >&2
exit 1

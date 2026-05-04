#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_target-path.sh
source "${script_dir}/_target-path.sh"

repo_root=$(git rev-parse --show-toplevel)
target=$(compute_target_path)

mkdir -p "$(dirname "$target")"

if [[ -L "$target" ]]; then
  current=$(resolve_symlink_target "$target")
  if [[ "$current" == "$repo_root" ]]; then
    echo "already linked: $target -> $repo_root"
    exit 0
  fi
  echo "removing existing symlink: $target -> $current"
  rm "$target"
elif [[ -e "$target" ]]; then
  ts=$(date +%s)
  backup="${target}.bak-${ts}"
  mv "$target" "$backup"
  echo "backed up real install to: $backup"
fi

ln -s "$repo_root" "$target"
echo "linked: $target -> $repo_root"
echo "restart Claude Code (or /plugin reload) to pick up changes if needed"

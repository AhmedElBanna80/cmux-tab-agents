#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_target-path.sh
source "${script_dir}/_target-path.sh"

repo_root=$(git rev-parse --show-toplevel)
target=$(compute_target_path)

if [[ -L "$target" ]]; then
  current=$(resolve_symlink_target "$target")
  if [[ "$current" == "$repo_root" ]]; then
    echo "linked: $target -> $repo_root"
  else
    echo "linked elsewhere: $target -> $current"
  fi
elif [[ -d "$target" ]]; then
  echo "installed (not linked): $target"
else
  echo "not installed"
fi

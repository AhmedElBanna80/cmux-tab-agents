#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_target-path.sh
source "${script_dir}/_target-path.sh"

repo_root=$(git rev-parse --show-toplevel)

# Print status for a single target linked to the given source.
status_one() {
  local target="$1"
  local source="$2"

  if [[ -L "$target" ]]; then
    local current
    current=$(resolve_symlink_target "$target")
    if [[ "$current" == "$source" ]]; then
      echo "linked: $target -> $source"
    else
      echo "linked elsewhere: $target -> $current"
    fi
  elif [[ -d "$target" ]]; then
    echo "installed (not linked): $target"
  else
    echo "not installed: $target"
  fi
}

cache_target=$(compute_target_path)
legacy_target=$(compute_legacy_target_path)
legacy_source="${repo_root}/skills/$(basename "$legacy_target")"

status_one "$cache_target" "$repo_root"
status_one "$legacy_target" "$legacy_source"

#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_target-path.sh
source "${script_dir}/_target-path.sh"

repo_root=$(git rev-parse --show-toplevel)

# Link a single target path to the given source path.
# Prints outcome. Returns 1 on failure, 0 on success.
link_one() {
  local target="$1"
  local source="$2"

  mkdir -p "$(dirname "$target")"

  if [[ -L "$target" ]]; then
    local current
    current=$(resolve_symlink_target "$target")
    if [[ "$current" == "$source" ]]; then
      echo "already linked: $target -> $source"
      return 0
    fi
    echo "removing existing symlink: $target -> $current"
    rm "$target"
  elif [[ -e "$target" ]]; then
    local ts backup
    ts=$(date +%s)
    backup="${target}.bak-${ts}"
    mv "$target" "$backup"
    echo "backed up real install to: $backup"
  fi

  if ln -s "$source" "$target"; then
    echo "linked: $target -> $source"
    return 0
  else
    echo "error: failed to symlink $target -> $source" >&2
    return 1
  fi
}

cache_target=$(compute_target_path)
legacy_target=$(compute_legacy_target_path)
legacy_source="${repo_root}/skills/$(basename "$legacy_target")"

exit_code=0
link_one "$cache_target" "$repo_root" || exit_code=1
link_one "$legacy_target" "$legacy_source" || exit_code=1

if [[ "$exit_code" -eq 0 ]]; then
  echo "restart Claude Code (or /plugin reload) to pick up changes if needed"
fi

exit "$exit_code"

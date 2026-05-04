#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_target-path.sh
source "${script_dir}/_target-path.sh"

repo_root=$(git rev-parse --show-toplevel)

# Unlink a single target that was linked to the given source.
# Prints outcome. Returns 1 on failure/warning, 0 on success.
unlink_one() {
  local target="$1"
  local source="$2"

  if [[ ! -e "$target" && ! -L "$target" ]]; then
    echo "not linked: $target"
    return 0
  fi

  if [[ -L "$target" ]]; then
    local current
    current=$(resolve_symlink_target "$target")
    if [[ "$current" != "$source" ]]; then
      echo "warning: $target is a symlink to '${current}', not expected source (${source}); refusing to remove" >&2
      return 1
    fi
    rm "$target"
    echo "unlinked: $target"

    local parent_dir base
    parent_dir=$(dirname "$target")
    base=$(basename "$target")
    shopt -s nullglob
    local backups
    backups=( "$parent_dir/$base".bak-* )
    shopt -u nullglob
    if [[ ${#backups[@]} -gt 0 ]]; then
      echo "found backup(s) — restore manually if you want the previous install:"
      local b
      for b in "${backups[@]}"; do
        echo "  mv \"$b\" \"$target\""
      done
    fi
    return 0
  fi

  echo "warning: $target is a real directory, not a symlink; refusing to remove" >&2
  return 1
}

cache_target=$(compute_target_path)
legacy_target=$(compute_legacy_target_path)
legacy_source="${repo_root}/skills/$(basename "$legacy_target")"

exit_code=0
unlink_one "$cache_target" "$repo_root" || exit_code=1
unlink_one "$legacy_target" "$legacy_source" || exit_code=1

exit "$exit_code"

#!/usr/bin/env bash
# Shared helper for link.sh, unlink.sh, and status.sh.
#
# Defines:
#   compute_target_path        - prints the absolute plugin-cache target path
#   compute_legacy_target_path - prints the absolute legacy ~/.claude/skills/ target path
#   resolve_symlink_target     - prints the absolute target a symlink points at
#
# When executed directly, prints the computed target path. When sourced, the
# functions become available without enabling strict mode in the caller.

# Private. Echoes "<name> <version>" or returns 1 with a message on stderr.
_read_manifest_fields() {
  local repo_root manifest name version

  if ! repo_root=$(git rev-parse --show-toplevel 2>/dev/null); then
    echo "error: not inside a git repository" >&2
    return 1
  fi

  manifest="${repo_root}/.claude-plugin/plugin.json"
  if [[ ! -f "$manifest" ]]; then
    echo "error: ${manifest} not found" >&2
    return 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required (install via: brew install jq)" >&2
    return 1
  fi

  name=$(jq -r '.name' "$manifest")
  version=$(jq -r '.version' "$manifest")

  if [[ -z "$name" || "$name" == "null" || -z "$version" || "$version" == "null" ]]; then
    echo "error: could not read name/version from ${manifest}" >&2
    return 1
  fi

  echo "$name $version"
}

compute_target_path() {
  local fields name version cache_root marketplace
  local matches=()
  local d

  fields=$(_read_manifest_fields) || return 1
  name=${fields%% *}
  version=${fields##* }

  cache_root="${HOME}/.claude/plugins/cache"

  if [[ -d "$cache_root" ]]; then
    for d in "$cache_root"/*/; do
      [[ -d "$d" ]] || continue
      if [[ -d "${d}${name}" ]]; then
        matches+=("$(basename "$d")")
      fi
    done
  fi

  if [[ ${#matches[@]} -eq 1 ]]; then
    marketplace="${matches[0]}"
  elif [[ ${#matches[@]} -gt 1 ]]; then
    echo "error: multiple marketplace dirs contain '${name}': ${matches[*]}" >&2
    echo "  remove the unwanted ones to disambiguate" >&2
    return 1
  else
    marketplace="$name"
  fi

  echo "${cache_root}/${marketplace}/${name}/${version}"
}

compute_legacy_target_path() {
  local fields name

  fields=$(_read_manifest_fields) || return 1
  name=${fields%% *}

  echo "${HOME}/.claude/skills/${name}"
}

resolve_symlink_target() {
  local link="$1"
  local current
  current=$(readlink "$link")
  if [[ "$current" != /* ]]; then
    current="$(cd "$(dirname "$link")" && cd "$current" 2>/dev/null && pwd)" || current=""
  fi
  echo "$current"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  compute_target_path
fi

#!/usr/bin/env bash
# resolve-agents-pane.sh — pick the cmux pane that tab-agents should spawn into.
#
# Echoes a single pane ref on stdout. Exits non-zero (with a diagnostic on
# stderr) if no usable pane can be resolved.
#
# Behavior is driven by the TOML key `agents_pane_layout`, looked up in this
# order (first match wins): per-repo `<repo>/.claude/cmux-tab-agents.toml`,
# then user-global `~/.claude/cmux-tab-agents.toml`. Default: "split".
#
#   split  (default)  Lazily create one sibling "agents" pane below the
#                     planner pane on first dispatch in a workspace, persist
#                     its ref to ~/.claude/cmux-tab-agents/workspaces/<id>.json,
#                     and reuse it on subsequent dispatches. If the saved ref
#                     is no longer present in `cmux list-panes`, recreate.
#   flat              Echo --caller-pane verbatim. No state, no cmux calls.
#   custom            Use the configured `agents_pane_ref`. Required; verified
#                     against `cmux list-panes`.
#
# Usage:
#   resolve-agents-pane.sh --caller-pane <ref> --caller-surface <ref> --workspace <id>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=_dispatch_common.sh
. "$SCRIPT_DIR/_dispatch_common.sh"

usage() {
  cat >&2 <<'EOF'
Usage: resolve-agents-pane.sh --caller-pane <ref> --caller-surface <ref> --workspace <id>
EOF
  exit 1
}

CALLER_PANE=""
CALLER_SURFACE=""
WORKSPACE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --caller-pane)    CALLER_PANE="$2";    shift 2 ;;
    --caller-surface) CALLER_SURFACE="$2"; shift 2 ;;
    --workspace)      WORKSPACE="$2";      shift 2 ;;
    -h|--help)        usage ;;
    *) echo "resolve-agents-pane: unknown arg '$1'" >&2; usage ;;
  esac
done

[[ -n "$CALLER_PANE" ]] || { echo "resolve-agents-pane: --caller-pane required" >&2; exit 1; }
[[ -n "$WORKSPACE"   ]] || { echo "resolve-agents-pane: --workspace required"   >&2; exit 1; }

# read_layout_config — echo (layout, agents_pane_ref) lookup chain.
# Per-repo TOML wins over user-global.
read_layout_config() {
  local key="$1"
  local repo_root value=""
  if repo_root=$(git rev-parse --show-toplevel 2>/dev/null); then
    value=$(read_toml_value "$repo_root/.claude/cmux-tab-agents.toml" "$key")
    [[ -n "$value" ]] && { printf '%s' "$value"; return 0; }
  fi
  value=$(read_toml_value "$HOME/.claude/cmux-tab-agents.toml" "$key")
  printf '%s' "$value"
}

LAYOUT="$(read_layout_config agents_pane_layout)"
[[ -z "$LAYOUT" ]] && LAYOUT="split"

case "$LAYOUT" in
  flat)
    printf '%s\n' "$CALLER_PANE"
    exit 0
    ;;
  custom)
    CUSTOM_REF="$(read_layout_config agents_pane_ref)"
    if [[ -z "$CUSTOM_REF" ]]; then
      echo "resolve-agents-pane: agents_pane_layout=custom requires agents_pane_ref in cmux-tab-agents.toml" >&2
      exit 1
    fi
    if ! cmux list-panes --workspace "$WORKSPACE" 2>/dev/null \
         | grep -Fxq -- "$CUSTOM_REF"; then
      echo "resolve-agents-pane: agents_pane_ref '$CUSTOM_REF' not found in workspace '$WORKSPACE' (cmux list-panes)" >&2
      exit 1
    fi
    printf '%s\n' "$CUSTOM_REF"
    exit 0
    ;;
  split)
    [[ -n "$CALLER_SURFACE" ]] || { echo "resolve-agents-pane: --caller-surface required for split layout (anchors the new pane on the planner's surface)" >&2; exit 1; }
    ;;
  *)
    echo "resolve-agents-pane: unknown agents_pane_layout '$LAYOUT' (expected: split, flat, custom)" >&2
    exit 1
    ;;
esac

# split mode: state file at ~/.claude/cmux-tab-agents/workspaces/<workspace>.json
STATE_DIR="$HOME/.claude/cmux-tab-agents/workspaces"
STATE_FILE="$STATE_DIR/${WORKSPACE}.json"

if [[ -f "$STATE_FILE" ]]; then
  EXISTING_REF="$(jq -r '.agents_pane_ref // empty' "$STATE_FILE" 2>/dev/null || true)"
  if [[ -n "$EXISTING_REF" ]]; then
    if cmux list-panes --workspace "$WORKSPACE" 2>/dev/null \
       | grep -Fxq -- "$EXISTING_REF"; then
      printf '%s\n' "$EXISTING_REF"
      exit 0
    fi
  fi
fi

# Create a new agents pane by splitting the planner's own surface downward.
# Using `cmux new-split --surface` (vs `cmux new-pane --workspace`) anchors
# the new pane to the caller's specific surface, so unrelated panes in the
# workspace are left untouched.
SPAWN_JSON=""
if ! SPAWN_JSON=$(cmux --json new-split down \
                   --surface "$CALLER_SURFACE" \
                   --focus false 2>/dev/null); then
  echo "resolve-agents-pane: cmux new-split failed for surface '$CALLER_SURFACE'" >&2
  exit 1
fi

NEW_REF="$(printf '%s' "$SPAWN_JSON" | jq -r '.pane_ref // .pane.ref // empty' 2>/dev/null)"
if [[ -z "$NEW_REF" ]]; then
  echo "resolve-agents-pane: could not parse pane_ref from cmux new-split output: $SPAWN_JSON" >&2
  exit 1
fi

# Atomic state write.
mkdir -p "$STATE_DIR"
TMP="${STATE_FILE}.tmp.$$"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq -n --arg ref "$NEW_REF" --arg ts "$NOW" \
  '{agents_pane_ref: $ref, created_at: $ts}' > "$TMP"
mv "$TMP" "$STATE_FILE"

printf '%s\n' "$NEW_REF"

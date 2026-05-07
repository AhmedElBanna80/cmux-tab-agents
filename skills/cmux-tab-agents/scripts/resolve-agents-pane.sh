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
#   split  (default)  Pick the pane directly below the planner if cmux
#                     geometry shows one (covers manual splits and TOCTOU
#                     races where another resolver already created the pane).
#                     Otherwise reuse the cached ref from
#                     ~/.claude/cmux-tab-agents/workspaces/<id>.json if it is
#                     still present in `cmux list-panes` (vertical-split edge
#                     case where the agents pane was created sideways).
#                     Otherwise lazily create one by splitting the planner's
#                     surface downward and persist the new ref.
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

# Short-circuit: if the caller is already inside the persisted agents pane,
# this is a recursive dispatch (e.g. implementer dispatching reviewers).
# Return immediately without consulting cmux geometry — that probe is only
# meaningful for top-level planner-dispatched cases, and racing geometry
# checks have produced spurious second agents panes when unrelated panes
# coincidentally satisfy the down-neighbor predicate.
if [[ -f "$STATE_FILE" ]]; then
  EXISTING_REF="$(jq -r '.agents_pane_ref // empty' "$STATE_FILE" 2>/dev/null || true)"
  if [[ -n "$EXISTING_REF" && "$CALLER_PANE" == "$EXISTING_REF" ]]; then
    printf '%s\n' "$CALLER_PANE"
    exit 0
  fi
fi

# persist_state — atomic write of agents_pane_ref to STATE_FILE.
persist_state() {
  local ref="$1" tmp now
  mkdir -p "$STATE_DIR"
  tmp="${STATE_FILE}.tmp.$$"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -n --arg ref "$ref" --arg ts "$now" \
    '{agents_pane_ref: $ref, created_at: $ts}' > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

# find_down_neighbor — echo the ref of the pane directly below CALLER_PANE in
# WORKSPACE (or empty if none). Cmux exposes pane geometry via
# `cmux --json list-panes --workspace`; the tree command does not include
# pixel_frame and split-direction metadata isn't surfaced anywhere else, so
# geometry is the only signal available. A pane is the down-neighbor when its
# top edge meets the caller's bottom edge (within a small pixel tolerance, to
# absorb fractional widths) AND the two panes have horizontal overlap.
find_down_neighbor() {
  local panes_json
  panes_json=$(cmux --json list-panes --workspace "$WORKSPACE" 2>/dev/null) || return 0
  [[ -n "$panes_json" ]] || return 0
  printf '%s' "$panes_json" | jq -r --arg caller "$CALLER_PANE" '
    (.panes // []) as $panes
    | ($panes[] | select(.ref == $caller) | .pixel_frame) as $c
    | if $c == null then empty
      else
        $panes[]
        | select(.ref != $caller)
        | select(.pixel_frame != null)
        | . as $p
        | ($c.y + $c.height) as $caller_bottom
        | ($c.x + $c.width)  as $caller_right
        | ($p.pixel_frame.x + $p.pixel_frame.width) as $p_right
        | select(($p.pixel_frame.y - $caller_bottom) | fabs < 5)
        | select($p.pixel_frame.x < $caller_right and $p_right > $c.x)
        | .ref
      end
  ' 2>/dev/null | head -n1
}

# Step 1: cmux geometry is authoritative — if a usable down-neighbor exists,
# reuse it and refresh the cache so subsequent runs skip this query.
DOWN_NEIGHBOR="$(find_down_neighbor)"
if [[ -n "$DOWN_NEIGHBOR" ]]; then
  persist_state "$DOWN_NEIGHBOR"
  printf '%s\n' "$DOWN_NEIGHBOR"
  exit 0
fi

# Step 2: no down-neighbor (e.g. planner sits at the bottom of a vertical split,
# so its agents pane was created sideways earlier). Trust the state file if
# it points at a pane that still exists.
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

# Step 3: critical section — guard the create path against concurrent
# dispatches with a mkdir-as-lock. mkdir is atomic on POSIX (EEXIST is
# returned to all but one process), portable everywhere, and trap-friendly
# on crash. Without this, two top-level dispatches racing into a fresh
# workspace each fire `cmux new-split` and produce duplicate agents panes.
mkdir -p "$STATE_DIR"
LOCK_DIR="$STATE_DIR/.lock.${WORKSPACE//\//_}"
ATTEMPTS=0
until mkdir "$LOCK_DIR" 2>/dev/null; do
  ATTEMPTS=$((ATTEMPTS + 1))
  if (( ATTEMPTS > 50 )); then
    echo "resolve-agents-pane: lock '$LOCK_DIR' held >5s; bailing" >&2
    exit 1
  fi
  sleep 0.1
done
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT INT TERM

# Re-check inside the lock — another racer may have completed the create
# path while we were waiting. This is the payoff: exactly one resolver in
# the cohort actually issues new-split.
if [[ -f "$STATE_FILE" ]]; then
  EXISTING_REF="$(jq -r '.agents_pane_ref // empty' "$STATE_FILE" 2>/dev/null || true)"
  if [[ -n "$EXISTING_REF" ]] \
     && cmux list-panes --workspace "$WORKSPACE" 2>/dev/null \
        | grep -Fxq -- "$EXISTING_REF"; then
    printf '%s\n' "$EXISTING_REF"
    exit 0
  fi
fi

# Genuinely first into the create path. Split the planner's own surface
# downward — `cmux new-split --surface` (vs `cmux new-pane --workspace`)
# anchors the new pane to the caller's specific surface, so unrelated panes
# in the workspace are left untouched.
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

persist_state "$NEW_REF"

printf '%s\n' "$NEW_REF"

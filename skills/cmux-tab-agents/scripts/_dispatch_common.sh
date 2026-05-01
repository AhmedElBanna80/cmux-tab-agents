#!/usr/bin/env bash
# _dispatch_common.sh — shared logic for dispatch-{implementer,spec-reviewer,code-reviewer}.sh
#
# Sourced by the three thin wrappers. Each wrapper sets PHASE before sourcing,
# then calls dispatch_main "$@".

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat >&2 <<EOF
Usage: $0 --ticket TICKET --title TITLE --slug SLUG \\
          (--task-text "TEXT" | --task-file PATH) \\
          [--type TYPE] \\
          [--planner-workspace REF] \\
          [--implementer-sha SHA] \\
          [--feedback-from-previous-review TEXT_OR_PATH]
EOF
  exit 1
}

# render_template <src> <dst>  — substitutes {{KEY}} placeholders from env vars.
# Reads source path and dest path from argv. Reads template values from env
# (TPL_TICKET, TPL_TITLE, TPL_SLUG, TPL_WORKTREE, TPL_PWS, TPL_IMPL_SHA,
# TPL_TASK, TPL_FEEDBACK) — passing through env avoids shell quoting issues
# with multiline task text and arbitrary review feedback.
render_template() {
  local src="$1" dst="$2"
  python3 - "$src" "$dst" <<'PY'
import os, sys
src, dst = sys.argv[1], sys.argv[2]
mapping = {
    "TICKET":            os.environ.get("TPL_TICKET", ""),
    "TITLE":             os.environ.get("TPL_TITLE", ""),
    "SLUG":              os.environ.get("TPL_SLUG", ""),
    "WORKTREE":          os.environ.get("TPL_WORKTREE", ""),
    "PLANNER_WORKSPACE": os.environ.get("TPL_PWS", ""),
    "IMPLEMENTER_SHA":   os.environ.get("TPL_IMPL_SHA", ""),
    "TASK":              os.environ.get("TPL_TASK", ""),
    "FEEDBACK":          os.environ.get("TPL_FEEDBACK", ""),
}
with open(src, "r", encoding="utf-8") as f:
    body = f.read()
for k, v in mapping.items():
    body = body.replace("{{" + k + "}}", v)
with open(dst, "w", encoding="utf-8") as f:
    f.write(body)
PY
}

dispatch_main() {
  local TICKET="" TITLE="" SLUG="" TASK_TEXT="" TASK_FILE=""
  local TYPE="" PLANNER_WS="" IMPL_SHA="" FEEDBACK=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ticket)              TICKET="$2"; shift 2 ;;
      --title)               TITLE="$2"; shift 2 ;;
      --slug)                SLUG="$2"; shift 2 ;;
      --task-text)           TASK_TEXT="$2"; shift 2 ;;
      --task-file)           TASK_FILE="$2"; shift 2 ;;
      --type)                TYPE="$2"; shift 2 ;;
      --planner-workspace)   PLANNER_WS="$2"; shift 2 ;;
      --implementer-sha)     IMPL_SHA="$2"; shift 2 ;;
      --feedback-from-previous-review) FEEDBACK="$2"; shift 2 ;;
      -h|--help)             usage ;;
      *) echo "$0: unknown arg '$1'" >&2; usage ;;
    esac
  done

  [[ -z "$TICKET" ]] && { echo "$0: --ticket required" >&2; usage; }
  [[ -z "$TITLE"  ]] && { echo "$0: --title required"  >&2; usage; }
  [[ -z "$SLUG"   ]] && { echo "$0: --slug required"   >&2; usage; }

  if [[ -n "$TASK_FILE" && -n "$TASK_TEXT" ]]; then
    echo "$0: pass exactly one of --task-text or --task-file" >&2; usage
  fi
  if [[ -z "$TASK_TEXT" && -z "$TASK_FILE" ]]; then
    echo "$0: --task-text or --task-file required" >&2; usage
  fi
  if [[ -n "$TASK_FILE" ]]; then
    [[ -r "$TASK_FILE" ]] || { echo "$0: cannot read --task-file '$TASK_FILE'" >&2; exit 1; }
    TASK_TEXT="$(cat "$TASK_FILE")"
  fi

  # If feedback arg is a readable file path, slurp it; else use as literal text.
  if [[ -n "$FEEDBACK" && -r "$FEEDBACK" ]]; then
    FEEDBACK="$(cat "$FEEDBACK")"
  fi

  # Default planner workspace = the dispatcher's own workspace.
  if [[ -z "$PLANNER_WS" ]]; then
    PLANNER_WS="${CMUX_WORKSPACE_ID:-}"
  fi
  if [[ -z "$PLANNER_WS" ]]; then
    echo "$0: not inside cmux (\$CMUX_WORKSPACE_ID is empty). Pass --planner-workspace explicitly." >&2
    exit 1
  fi

  # 1. Provision worktree (idempotent).
  local ENSURE="$SCRIPT_DIR/ensure-worktree.sh"
  local WT
  local ensure_args=(--ticket "$TICKET" --slug "$SLUG")
  [[ -n "$TYPE" ]] && ensure_args+=(--type "$TYPE")
  if ! WT=$("$ENSURE" "${ensure_args[@]}"); then
    echo "$0: ensure-worktree failed for $TICKET" >&2
    exit 1
  fi

  # 2. Render seed prompt for this phase.
  local TEMPLATE="$SKILL_ROOT/prompts/${PHASE}-tab-prompt.md"
  [[ -r "$TEMPLATE" ]] || { echo "$0: missing template $TEMPLATE" >&2; exit 1; }

  local RENDERED="$WT/.cmux-tab-prompt-${PHASE}.md"
  TPL_TICKET="$TICKET" TPL_TITLE="$TITLE" TPL_SLUG="$SLUG" TPL_WORKTREE="$WT" \
    TPL_PWS="$PLANNER_WS" TPL_IMPL_SHA="$IMPL_SHA" TPL_TASK="$TASK_TEXT" \
    TPL_FEEDBACK="$FEEDBACK" \
    render_template "$TEMPLATE" "$RENDERED"

  # 3. Spawn a new tab in the planner's pane.
  # NOTE: $CMUX_PANEL_ID is the *surface* ID, not the pane. Resolve the pane
  # ref via `cmux identify --json` instead.
  local pane
  pane=$(cmux --json identify 2>/dev/null | python3 -c \
    'import sys,json; d=json.load(sys.stdin); print(d.get("caller",{}).get("pane_ref") or d.get("focused",{}).get("pane_ref",""))' 2>/dev/null) || true
  if [[ -z "$pane" ]]; then
    echo "$0: cannot determine current pane (cmux identify failed; not running inside a cmux tab?)" >&2
    exit 1
  fi

  local SPAWN_JSON
  if ! SPAWN_JSON=$(cmux --json new-surface --type terminal --pane "$pane" 2>/dev/null); then
    echo "$0: cmux new-surface failed" >&2
    exit 1
  fi

  local SURFACE
  SURFACE=$(printf '%s' "$SPAWN_JSON" | python3 -c \
    'import sys,json; d=json.load(sys.stdin); print(d.get("surface_ref") or d.get("surface",{}).get("ref",""))' 2>/dev/null)
  [[ -z "$SURFACE" ]] && { echo "$0: could not parse surface ref from: $SPAWN_JSON" >&2; exit 1; }

  # 3a. Rename the tab BEFORE booting claude. cmux re-titles tabs to the
  # foreground process name (e.g. "Claude Code") when claude takes over, so
  # the seed prompt's rename inside the agent often gets clobbered. Setting
  # the title against the pre-claude shell makes the custom title stick.
  cmux rename-tab --surface "$SURFACE" "${TICKET}: ${TITLE}" >/dev/null 2>&1 || true

  # 4. Boot the tab: cd into the worktree, then launch claude with the seed.
  # The boot one-liner reads the rendered prompt at runtime via $(cat ...) so
  # we don't have to embed multi-KB of prompt text in a `cmux send` payload.
  # The shell prompt accepts \n as Enter (so cd && claude runs immediately);
  # we fire `send-key enter` separately as a safety net for terminals where
  # the trailing newline is interpreted differently.
  cmux send --surface "$SURFACE" \
    "cd $WT && claude --dangerously-skip-permissions --append-system-prompt \"\$(cat $RENDERED)\""$'\n'
  cmux send-key --surface "$SURFACE" enter >/dev/null 2>&1 || true

  # 5. Set initial dispatch pill on the planner's workspace.
  cmux set-status "${TICKET}-${PHASE}" "dispatched" \
    --icon clock --color "#ff9500" \
    --workspace "$PLANNER_WS" >/dev/null 2>&1 || true

  # 6. Emit the surface ref for the planner.
  echo "$SURFACE"
}

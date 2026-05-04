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
          [--planner-surface REF] \\
          [--model MODEL_ID] \\
          [--effort LEVEL] \\
          [--implementer-sha SHA] \\
          [--feedback-from-previous-review TEXT_OR_PATH]
EOF
  exit 1
}

# _read_toml_value <file> <key> — naive TOML-flat-key lookup. Echoes the value
# (with surrounding "..." or '...' stripped) to stdout. Returns 1 if file is
# missing or key is absent. Intentionally matches the parser used by
# ensure-worktree.sh for consistency.
_read_toml_value() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 1
  local line
  line=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" 2>/dev/null | head -1) || return 1
  [[ -n "$line" ]] || return 1
  printf '%s' "$line" \
    | sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//" \
    | sed -E 's/^"(.*)"$/\1/' \
    | sed -E "s/^'(.*)'\$/\1/"
}

# resolve_default <toml_key> <env_var_name> <cli_value>
# Returns the first non-empty value among (in order):
#   1. <cli_value>
#   2. ${<env_var_name>}                 (indirect expansion)
#   3. <toml_key> in $REPO_CONFIG        (per-repo .claude/cmux-tab-agents.toml)
#   4. <toml_key> in $USER_CONFIG        (user-global ~/.claude/cmux-tab-agents.toml)
# Echoes empty if none set. Caller decides whether unset → flag-omitted.
resolve_default() {
  local key="$1" env_name="$2" cli="$3"
  if [[ -n "$cli" ]]; then
    printf '%s' "$cli"
    return 0
  fi
  local env_val="${!env_name:-}"
  if [[ -n "$env_val" ]]; then
    printf '%s' "$env_val"
    return 0
  fi
  local v
  if [[ -n "${REPO_CONFIG:-}" && -f "${REPO_CONFIG:-}" ]]; then
    if v=$(_read_toml_value "$REPO_CONFIG" "$key") && [[ -n "$v" ]]; then
      printf '%s' "$v"
      return 0
    fi
  fi
  if [[ -n "${USER_CONFIG:-}" && -f "${USER_CONFIG:-}" ]]; then
    if v=$(_read_toml_value "$USER_CONFIG" "$key") && [[ -n "$v" ]]; then
      printf '%s' "$v"
      return 0
    fi
  fi
  printf ''
}

# resolved_boot_flags — emit the trailing " --model X --effort Y" segment of
# the claude boot command. Reads $RESOLVED_MODEL / $RESOLVED_EFFORT from the
# environment. Empty when neither is set; leading space when at least one is.
resolved_boot_flags() {
  local out=""
  if [[ -n "${RESOLVED_MODEL:-}" ]]; then
    out+=" --model ${RESOLVED_MODEL}"
  fi
  if [[ -n "${RESOLVED_EFFORT:-}" ]]; then
    out+=" --effort ${RESOLVED_EFFORT}"
  fi
  printf '%s' "$out"
}

# claude_boot_command <worktree> <rendered_path> — emit the shell one-liner
# that boots the tab-agent's claude process. Reads $RESOLVED_MODEL /
# $RESOLVED_EFFORT via resolved_boot_flags.
claude_boot_command() {
  local wt="$1" rendered="$2"
  printf 'cd %s && claude --dangerously-skip-permissions%s --append-system-prompt "$(cat %s)"' \
    "$wt" "$(resolved_boot_flags)" "$rendered"
}

# render_template <src> <dst>  — substitutes {{KEY}} placeholders from env vars.
# Reads source path and dest path from argv. Reads template values from env
# (TPL_TICKET, TPL_TITLE, TPL_SLUG, TPL_WORKTREE, TPL_PWS, TPL_PSURF,
# TPL_IMPL_SHA, TPL_TASK, TPL_FEEDBACK) — passing through env avoids shell
# quoting issues with multiline task text and arbitrary review feedback.
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
    "PLANNER_SURFACE":   os.environ.get("TPL_PSURF", ""),
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
  local TYPE="" PLANNER_WS="" PLANNER_SURFACE="" MODEL="" EFFORT="" IMPL_SHA="" FEEDBACK=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ticket)              TICKET="$2"; shift 2 ;;
      --title)               TITLE="$2"; shift 2 ;;
      --slug)                SLUG="$2"; shift 2 ;;
      --task-text)           TASK_TEXT="$2"; shift 2 ;;
      --task-file)           TASK_FILE="$2"; shift 2 ;;
      --type)                TYPE="$2"; shift 2 ;;
      --planner-workspace)   PLANNER_WS="$2"; shift 2 ;;
      --planner-surface)     PLANNER_SURFACE="$2"; shift 2 ;;
      --model)               MODEL="$2"; shift 2 ;;
      --effort)              EFFORT="$2"; shift 2 ;;
      --implementer-sha)     IMPL_SHA="$2"; shift 2 ;;
      --feedback-from-previous-review) FEEDBACK="$2"; shift 2 ;;
      -h|--help)             usage ;;
      *) echo "$0: unknown arg '$1'" >&2; usage ;;
    esac
  done

  if [[ -n "$EFFORT" ]]; then
    case "$EFFORT" in
      low|medium|high|xhigh|max) ;;
      *) echo "$0: --effort must be one of low|medium|high|xhigh|max (got '$EFFORT')" >&2; exit 1 ;;
    esac
  fi

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

  # Identify the dispatcher's own cmux surface and pane up front. The caller
  # surface_ref doubles as the default --planner-surface (so the spawned tab
  # can push status messages back to the planner's input box) and the caller
  # pane_ref is reused later when spawning the child surface.
  local IDENTIFY_JSON CALLER_SURFACE CALLER_PANE
  IDENTIFY_JSON=$(cmux --json identify 2>/dev/null) || IDENTIFY_JSON=""
  CALLER_SURFACE=$(printf '%s' "$IDENTIFY_JSON" | python3 -c \
    'import sys,json
try:
    d=json.load(sys.stdin)
except Exception:
    sys.exit(0)
print(d.get("caller",{}).get("surface_ref") or d.get("focused",{}).get("surface_ref",""))' \
    2>/dev/null) || CALLER_SURFACE=""
  CALLER_PANE=$(printf '%s' "$IDENTIFY_JSON" | python3 -c \
    'import sys,json
try:
    d=json.load(sys.stdin)
except Exception:
    sys.exit(0)
print(d.get("caller",{}).get("pane_ref") or d.get("focused",{}).get("pane_ref",""))' \
    2>/dev/null) || CALLER_PANE=""

  # Default planner surface = the dispatcher's own surface. Tab-agents push
  # one terminal-state message to this surface so the planner doesn't have to
  # poll. Empty value disables push.
  if [[ -z "$PLANNER_SURFACE" ]]; then
    PLANNER_SURFACE="$CALLER_SURFACE"
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

  # 1a. Resolve layered defaults for --model and --effort.
  # Order: cli > env > per-repo TOML > user-global TOML > unset. The TOML
  # files share the format documented in references/configuration.md.
  local _REPO_ROOT
  _REPO_ROOT=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null) || _REPO_ROOT=""
  local REPO_CONFIG="" USER_CONFIG="$HOME/.claude/cmux-tab-agents.toml"
  [[ -n "$_REPO_ROOT" ]] && REPO_CONFIG="$_REPO_ROOT/.claude/cmux-tab-agents.toml"
  export REPO_CONFIG USER_CONFIG
  local RESOLVED_MODEL RESOLVED_EFFORT
  RESOLVED_MODEL=$(resolve_default default_model CMUX_TAB_AGENTS_DEFAULT_MODEL "$MODEL")
  RESOLVED_EFFORT=$(resolve_default default_effort CMUX_TAB_AGENTS_DEFAULT_EFFORT "$EFFORT")
  if [[ -n "$RESOLVED_EFFORT" ]]; then
    case "$RESOLVED_EFFORT" in
      low|medium|high|xhigh|max) ;;
      *)
        echo "$0: resolved default_effort='$RESOLVED_EFFORT' is not one of low|medium|high|xhigh|max." >&2
        echo "    Check $REPO_CONFIG and $USER_CONFIG, or unset CMUX_TAB_AGENTS_DEFAULT_EFFORT." >&2
        exit 1
        ;;
    esac
  fi
  export RESOLVED_MODEL RESOLVED_EFFORT

  # 2. Render seed prompt for this phase.
  local TEMPLATE="$SKILL_ROOT/prompts/${PHASE}-tab-prompt.md"
  [[ -r "$TEMPLATE" ]] || { echo "$0: missing template $TEMPLATE" >&2; exit 1; }

  local RENDERED="$WT/.cmux-tab-prompt-${PHASE}.md"
  TPL_TICKET="$TICKET" TPL_TITLE="$TITLE" TPL_SLUG="$SLUG" TPL_WORKTREE="$WT" \
    TPL_PWS="$PLANNER_WS" TPL_PSURF="$PLANNER_SURFACE" \
    TPL_IMPL_SHA="$IMPL_SHA" TPL_TASK="$TASK_TEXT" TPL_FEEDBACK="$FEEDBACK" \
    render_template "$TEMPLATE" "$RENDERED"

  # 3. Spawn a new tab in the planner's pane. Reuse the pane ref we already
  # resolved via `cmux identify` above.
  if [[ -z "$CALLER_PANE" ]]; then
    echo "$0: cannot determine current pane (cmux identify failed; not running inside a cmux tab?)" >&2
    exit 1
  fi

  local SPAWN_JSON
  if ! SPAWN_JSON=$(cmux --json new-surface --type terminal --pane "$CALLER_PANE" 2>/dev/null); then
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
  # the trailing newline is interpreted differently. claude_boot_command reads
  # $RESOLVED_MODEL / $RESOLVED_EFFORT and splices them into the boot string.
  local BOOT
  BOOT=$(claude_boot_command "$WT" "$RENDERED")
  cmux send --surface "$SURFACE" "${BOOT}"$'\n'
  cmux send-key --surface "$SURFACE" enter >/dev/null 2>&1 || true

  # 5. Set initial dispatch pill on the planner's workspace.
  cmux set-status "${TICKET}-${PHASE}" "dispatched" \
    --icon clock --color "#ff9500" \
    --workspace "$PLANNER_WS" >/dev/null 2>&1 || true

  # 6. Emit the surface ref for the planner.
  echo "$SURFACE"
}

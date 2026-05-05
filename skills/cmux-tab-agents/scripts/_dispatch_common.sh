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
          [--feedback-from-previous-review TEXT_OR_PATH] \\
          [--fix-only]
EOF
  exit 1
}

# resolve_model_for_phase <phase> [--model MODEL_ID]
# Resolves the model for a given phase.
# Precedence: --model flag (if provided) > repo config [models].<phase> > (empty)
# Phase names are normalized (hyphens → underscores) before config lookup.
# Returns the model ID if found, empty otherwise.
resolve_model_for_phase() {
  local phase="$1"
  local explicit_model=""

  # Check for optional --model flag
  if [[ $# -gt 1 && "$2" == "--model" && $# -gt 2 ]]; then
    explicit_model="$3"
  fi

  # If explicit --model passed, use it (highest precedence)
  if [[ -n "$explicit_model" ]]; then
    echo "$explicit_model"
    return 0
  fi

  # Normalize phase name: hyphens → underscores (dispatch passes 'spec-reviewer', config uses 'spec_reviewer')
  phase="${phase//-/_}"

  # Try to read from repo config [models] section
  local repo_root
  if repo_root=$(git rev-parse --show-toplevel 2>/dev/null); then
    local config_file="$repo_root/.claude/cmux-tab-agents.toml"
    if [[ -f "$config_file" ]]; then
      # Extract from [models] section: find [models], read until next [, extract phase = value
      local value
      value=$(sed -n '/^\[models\]/,/^\[/p' "$config_file" \
        | grep -E "^[[:space:]]*${phase}[[:space:]]*=" \
        | head -1 \
        | sed -E "s/^[[:space:]]*${phase}[[:space:]]*=[[:space:]]*//" \
        | sed -E 's/^"(.*)"$/\1/' \
        | sed -E "s/^'(.*)'\$/\1/" \
        || true)
      if [[ -n "$value" ]]; then
        echo "$value"
        return 0
      fi
    fi
  fi

  # No model found, return empty
  return 0
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

# read_toml_value <file> <key> — extract a TOML top-level key value.
# Assumes flat structure: key = "value" or key = value (no nested tables, no multi-line).
# Echoes the value (quotes stripped), or empty string if not found or file missing.
read_toml_value() {
  local file="$1" key="$2"
  [[ -r "$file" ]] || return
  grep -E "^$key\s*=" "$file" 2>/dev/null | sed -e 's/.*=\s*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' | head -1
}

# resolve_setting <name> <cli_value> <repo_root> — resolve a setting (MODEL or EFFORT).
# Resolution order (first match wins):
# 1. CLI flag value (if non-empty)
# 2. Env var CMUX_TAB_AGENTS_DEFAULT_<NAME>
# 3. Per-repo TOML: <repo_root>/.claude/cmux-tab-agents.toml key default_<name_lower>
# 4. User-global TOML: ~/.claude/cmux-tab-agents.toml, same key
# 5. Empty (claude uses its own default)
resolve_setting() {
  local name="$1" cli_value="$2" repo_root="$3"
  local env_var="CMUX_TAB_AGENTS_DEFAULT_${name}"
  local toml_key
  toml_key="default_$(echo "$name" | tr '[:upper:]' '[:lower:]')"
  local result=""

  # Step 1: CLI value
  if [[ -n "$cli_value" ]]; then
    echo "$cli_value"
    return
  fi

  # Step 2: Env var
  if [[ -n "${!env_var:-}" ]]; then
    echo "${!env_var}"
    return
  fi

  # Step 3: Per-repo TOML (repo_root must be provided)
  if [[ -n "$repo_root" ]]; then
    result=$(read_toml_value "$repo_root/.claude/cmux-tab-agents.toml" "$toml_key")
    [[ -n "$result" ]] && { echo "$result"; return; }
  fi

  # Step 4: User-global TOML
  result=$(read_toml_value "$HOME/.claude/cmux-tab-agents.toml" "$toml_key")
  [[ -n "$result" ]] && { echo "$result"; return; }

  # Step 5: Unset (empty)
  echo ""
}

dispatch_main() {
  local TICKET="" TITLE="" SLUG="" TASK_TEXT="" TASK_FILE=""
  local TYPE="" PLANNER_WS="" PLANNER_SURFACE="" MODEL="" EFFORT="" IMPL_SHA="" FEEDBACK="" FIX_ONLY=0

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
      --fix-only)            FIX_ONLY=1; shift ;;
      -h|--help)             usage ;;
      *) echo "$0: unknown arg '$1'" >&2; usage ;;
    esac
  done

  [[ -z "$TICKET" ]] && { echo "$0: --ticket required" >&2; usage; }
  [[ -z "$TITLE"  ]] && { echo "$0: --title required"  >&2; usage; }
  [[ -z "$SLUG"   ]] && { echo "$0: --slug required"   >&2; usage; }

  # --fix-only mode: feedback required, task optional
  if [[ $FIX_ONLY -eq 1 ]]; then
    [[ -z "$FEEDBACK" ]] && { echo "$0: --fix-only requires --feedback-from-previous-review" >&2; usage; }
  else
    # Normal mode: task required
    if [[ -n "$TASK_FILE" && -n "$TASK_TEXT" ]]; then
      echo "$0: pass exactly one of --task-text or --task-file" >&2; usage
    fi
    if [[ -z "$TASK_TEXT" && -z "$TASK_FILE" ]]; then
      echo "$0: --task-text or --task-file required" >&2; usage
    fi
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

  # 2. Render seed prompt for this phase.
  local TEMPLATE
  if [[ $FIX_ONLY -eq 1 && "$PHASE" == "implementer" ]]; then
    TEMPLATE="$SKILL_ROOT/prompts/${PHASE}-fix-only-tab-prompt.md"
  else
    TEMPLATE="$SKILL_ROOT/prompts/${PHASE}-tab-prompt.md"
  fi
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

  # 4. Resolve model and effort through layered defaults:
  #    MODEL: CLI flag > phase-specific [models].<phase> > default_model > (none)
  #    EFFORT: CLI flag > env var > per-repo TOML > user-global TOML > (none)
  # Get repo root for per-repo config lookups.
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || repo_root="."

  # Resolve MODEL: check CLI with --model flag, then phase-specific config, then generic defaults.
  local resolved_model=""
  if [[ -n "$MODEL" ]]; then
    resolved_model=$(resolve_model_for_phase "$PHASE" --model "$MODEL")
  else
    # Try phase-specific [models].<phase> config
    resolved_model=$(resolve_model_for_phase "$PHASE") || resolved_model=""
    # If not found, try generic default_model
    if [[ -z "$resolved_model" ]]; then
      resolved_model=$(resolve_setting MODEL "" "$repo_root") || resolved_model=""
    fi
  fi

  # Resolve EFFORT: use generic resolve_setting (CLI > env > per-repo TOML > user-global TOML).
  local resolved_effort
  resolved_effort=$(resolve_setting EFFORT "$EFFORT" "$repo_root") || resolved_effort=""

  local model_flag="" effort_flag=""
  [[ -n "$resolved_model" ]] && model_flag=" --model $resolved_model"
  [[ -n "$resolved_effort" ]] && effort_flag=" --effort $resolved_effort"

  # 5. Boot the tab: cd into the worktree, then launch claude with the seed.
  # The boot one-liner reads the rendered prompt at runtime via $(cat ...) so
  # we don't have to embed multi-KB of prompt text in a `cmux send` payload.
  # The shell prompt accepts \n as Enter (so cd && claude runs immediately);
  # we fire `send-key enter` separately as a safety net for terminals where
  # the trailing newline is interpreted differently.
  # Pass an initial user message as the trailing positional arg to claude so
  # the agent fires immediately on boot instead of idling on the welcome
  # screen. Avoids the fragile backgrounded `( sleep N; cmux send ... ) &`
  # nudge that gets SIGHUP'd when the dispatcher exits.
  cmux send --surface "$SURFACE" \
    "cd $WT && claude --dangerously-skip-permissions${model_flag}${effort_flag} --append-system-prompt \"\$(cat $RENDERED)\" \"Begin executing the task per the system prompt.\""$'\n'
  cmux send-key --surface "$SURFACE" enter >/dev/null 2>&1 || true

  # 6. Set initial dispatch pill on the planner's workspace.
  cmux set-status "${TICKET}-${PHASE}" "dispatched" \
    --icon clock --color "#ff9500" \
    --workspace "$PLANNER_WS" >/dev/null 2>&1 || true

  # 7. Emit the surface ref for the planner.
  echo "$SURFACE"
}

#!/usr/bin/env bash
# workspace-state.sh — per-workspace state for cmux-tab-agents.
#
# Tracks the surface refs spawned per ticket/phase so finish-task.sh can emit
# a cleanup manifest after both reviewers approve. State lives at
# ~/.claude/cmux-tab-agents/workspaces/<WORKSPACE_ID>.json.
#
# Sourced by dispatch-*.sh, finish-task.sh, and task-adapter.sh.
#
# Public functions:
#   get_workspace_id              echo $CMUX_WORKSPACE_ID (empty if unset)
#   get_state_file_path           echo state file path for current workspace
#   init_workspace_state          create/initialize state file (idempotent)
#   add_surface T P REF           record surface_ref REF for ticket T, phase P
#   get_ticket_surfaces T         echo JSON object of phase→surface for ticket T
#   get_surface_ref T P           echo surface_ref for ticket T, phase P
#   mark_ticket_done T            set tickets[T].status = "done"
#   remove_ticket T               delete tickets[T] entry

set -uo pipefail

get_workspace_id() {
  printf '%s' "${CMUX_WORKSPACE_ID:-}"
}

get_state_file_path() {
  local wsid
  wsid=$(get_workspace_id)
  [[ -z "$wsid" ]] && return 0
  printf '%s/.claude/cmux-tab-agents/workspaces/%s.json' "$HOME" "$wsid"
}

init_workspace_state() {
  local f
  f=$(get_state_file_path)
  [[ -z "$f" ]] && return 0
  if [[ -f "$f" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$f")"
  local wsid
  wsid=$(get_workspace_id)
  WSID="$wsid" FPATH="$f" python3 - <<'PY'
import json, os
data = {"workspace_id": os.environ["WSID"], "tickets": {}}
tmp = os.environ["FPATH"] + ".tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
os.replace(tmp, os.environ["FPATH"])
PY
}

# _ws_mutate <python-snippet> — read state, expose dict `d`, write back atomically.
_ws_mutate() {
  local f
  f=$(get_state_file_path)
  [[ -z "$f" ]] && return 0
  init_workspace_state
  FPATH="$f" python3 - "$@" <<'PY'
import json, os, sys
path = os.environ["FPATH"]
with open(path, "r", encoding="utf-8") as fh:
    d = json.load(fh)
d.setdefault("tickets", {})
exec(sys.argv[1], {"d": d, "args": sys.argv[2:]})
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(d, fh, indent=2)
    fh.write("\n")
os.replace(tmp, path)
PY
}

add_surface() {
  local ticket="$1" phase="$2" ref="$3"
  _ws_mutate '
t, p, r = args
entry = d["tickets"].setdefault(t, {"status": "active", "surfaces": {}})
entry.setdefault("surfaces", {})[p] = r
' "$ticket" "$phase" "$ref"
}

get_ticket_surfaces() {
  local ticket="$1"
  local f
  f=$(get_state_file_path)
  if [[ -z "$f" || ! -f "$f" ]]; then
    printf '{}'
    return 0
  fi
  FPATH="$f" TICKET="$ticket" python3 - <<'PY'
import json, os
with open(os.environ["FPATH"], "r", encoding="utf-8") as fh:
    d = json.load(fh)
entry = d.get("tickets", {}).get(os.environ["TICKET"], {})
print(json.dumps(entry.get("surfaces", {})), end="")
PY
}

get_surface_ref() {
  local ticket="$1" phase="$2"
  local f
  f=$(get_state_file_path)
  if [[ -z "$f" || ! -f "$f" ]]; then
    return 0
  fi
  FPATH="$f" TICKET="$ticket" PHASE="$phase" python3 - <<'PY'
import json, os
with open(os.environ["FPATH"], "r", encoding="utf-8") as fh:
    d = json.load(fh)
ref = d.get("tickets", {}).get(os.environ["TICKET"], {}).get("surfaces", {}).get(os.environ["PHASE"], "")
print(ref, end="")
PY
}

mark_ticket_done() {
  local ticket="$1"
  _ws_mutate '
t, = args
entry = d["tickets"].setdefault(t, {"status": "active", "surfaces": {}})
entry["status"] = "done"
' "$ticket"
}

remove_ticket() {
  local ticket="$1"
  _ws_mutate '
t, = args
d["tickets"].pop(t, None)
' "$ticket"
}

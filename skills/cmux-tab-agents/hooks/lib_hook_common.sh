#!/usr/bin/env bash
# lib_hook_common.sh — shared helpers sourced by the SessionStart / PostToolUse / Stop hooks.
#
# Contract:
#   - Hooks read Claude Code's standard hook JSON on stdin (see
#     https://docs.claude.com/en/docs/claude-code/hooks). We use only fields
#     documented as stable: session_id, cwd, tool_name, tool_input,
#     tool_response, transcript_path.
#   - Routing identifiers (TICKET, PHASE, PLANNER_WORKSPACE) are NOT in the
#     hook payload. They are written by the dispatch script to the worktree's
#     `.cmux-state/dispatch.json` before booting `claude`. Hooks read that
#     file via `cwd`.
#   - Hooks must never fail the agent. Each helper swallows errors and
#     returns empty/sentinel values when something is missing.

# Read the entire hook stdin payload into HOOK_STDIN_JSON exactly once.
# Must be called at the top level of the hook script BEFORE any `$(...)`
# substitution, otherwise the first subshell consumes stdin and later
# helpers see an empty payload. The variable is exported so subshells
# inherit it.
hook_read_stdin() {
  if [[ -n "${HOOK_STDIN_JSON+set}" ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    HOOK_STDIN_JSON=$(cat 2>/dev/null || true)
  else
    HOOK_STDIN_JSON=""
  fi
  export HOOK_STDIN_JSON
}

# Extract a top-level field from the hook payload. Echoes empty if missing
# or if jq is unavailable. Usage: hook_field <field-name>
hook_field() {
  hook_read_stdin
  local field="$1"
  [[ -z "$HOOK_STDIN_JSON" ]] && return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -r --arg k "$field" '.[$k] // empty' <<<"$HOOK_STDIN_JSON" 2>/dev/null || true
}

# Locate the worktree root for the current hook invocation. Strategy:
#   1. Walk up from `cwd` (from the hook payload, falling back to $PWD)
#      looking for a directory that contains `.cmux-state/dispatch.json`.
#   2. Echo the directory on success; echo nothing on failure.
hook_locate_worktree() {
  local cwd
  cwd=$(hook_field cwd)
  [[ -z "$cwd" ]] && cwd="$PWD"
  [[ -d "$cwd" ]] || return 0

  local dir="$cwd"
  while [[ "$dir" != "/" && -n "$dir" ]]; do
    if [[ -f "$dir/.cmux-state/dispatch.json" ]]; then
      printf '%s' "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 0
}

# Read a string field from `<worktree>/.cmux-state/dispatch.json`. Echoes
# empty if the file is missing, jq is missing, or the field is absent.
# Usage: hook_dispatch_field <worktree> <field-name>
hook_dispatch_field() {
  local wt="$1" field="$2"
  [[ -n "$wt" && -f "$wt/.cmux-state/dispatch.json" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -r --arg k "$field" '.[$k] // empty' "$wt/.cmux-state/dispatch.json" 2>/dev/null || true
}

# Best-effort cmux invocation. cmux is not present in CI / test environments;
# missing or failing calls must not propagate. All output is suppressed.
hook_cmux() {
  command -v cmux >/dev/null 2>&1 || return 0
  cmux "$@" >/dev/null 2>&1 || true
}

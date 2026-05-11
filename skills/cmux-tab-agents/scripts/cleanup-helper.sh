#!/usr/bin/env bash
# cleanup-helper.sh — planner-side cleanup helper for cmux-tab-agents
#
# Subcommands (all dry-run by default; pass --apply to mutate):
#   discover [--apply]               — emit JSON of four cleanup-candidate categories;
#                                       with --apply, also runs each apply step in one pass
#   close-surfaces [--apply] [--verbose] <ref>…  — close idle cmux surfaces
#                                       (--verbose prints per-surface details)
#   remove-worktrees [--apply] <path>… — remove stale worktree directories
#   delete-branches [--apply] <repo> <branch>… — delete merged git branches (safe: -d only)
#   prune-streams [--apply] <path>…  — remove orphaned agent JSONL event files
#
# Environment overrides for discover:
#   CMUX_TAB_AGENTS_WORKTREE_BASE  (default: ~/POC/worktrees/cmux-tab-agents)
#   CMUX_TAB_AGENTS_AGENTS_DIR     (default: ~/.cmux-tab-agents/agents)
#
# Idleness heuristic (v1, fixed): events file mtime > 30 minutes old.

set -euo pipefail

IDLE_THRESHOLD_SECONDS=1800  # 30 minutes

log()  { printf '[cleanup-helper] %s\n' "$*" >&2; }
error(){ printf '[cleanup-helper ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
  cat >&2 <<'EOF'
Usage: cleanup-helper.sh <subcommand> [--apply] [args...]

Subcommands:
  discover [--apply]                Emit JSON with cleanup candidates;
                                    with --apply, immediately runs each apply step
  close-surfaces [--apply] [--verbose] <ref>…   Close idle cmux surfaces (dry-run by default;
                                                 --verbose prints per-surface details)
  remove-worktrees [--apply] <p>…   Remove stale worktree directories (dry-run by default)
  delete-branches [--apply] <repo> <branch>…  Delete merged branches via git branch -d (dry-run by default)
  prune-streams [--apply] <path>…   Remove orphaned agent JSONL files (dry-run by default)

Pass --apply to actually mutate; omit for dry-run (safe default).
EOF
  exit 1
}

# ── helpers ────────────────────────────────────────────────────────────────────

_file_age_seconds() {
  local f="$1"
  [[ -f "$f" ]] || { printf '999999'; return; }
  local now mtime
  now=$(date +%s)
  if stat --version 2>/dev/null | grep -q GNU; then
    mtime=$(stat -c %Y "$f" 2>/dev/null || printf '0')
  else
    mtime=$(stat -f %m "$f" 2>/dev/null || printf '0')
  fi
  printf '%d' $((now - mtime))
}

_is_stale() {
  local f="$1"
  local age
  age=$(_file_age_seconds "$f")
  [[ "$age" -ge "$IDLE_THRESHOLD_SECONDS" ]]
}

_ticket_from_path() {
  local path="$1"
  # Extracts ticket from paths like .../ISSUE-103/cmux-tab-agents
  basename "$(dirname "$path")"
}

_branch_from_ticket() {
  # Enumerate branches that contain the ticket string
  local repo="$1" ticket="$2"
  git -C "$repo" branch --list "*${ticket}*" 2>/dev/null | sed 's/^[* ]*//'
}

_pr_is_merged() {
  local ticket="$1"
  local result
  result=$(gh pr list --state merged --search "$ticket" --limit 50 2>/dev/null || true)
  [[ -n "$result" ]]
}

# ── discover ───────────────────────────────────────────────────────────────────

cmd_discover() {
  local apply=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply) apply=true; shift ;;
      *) shift ;;
    esac
  done

  local worktree_base="${CMUX_TAB_AGENTS_WORKTREE_BASE:-$HOME/POC/worktrees/cmux-tab-agents}"
  local agents_dir="${CMUX_TAB_AGENTS_AGENTS_DIR:-$HOME/.cmux-tab-agents/agents}"

  # category accumulators (JSON arrays built as shell strings)
  local idle_surfaces="[]"
  local merged_worktrees="[]"
  local merged_branches="[]"
  local stale_streams="[]"

  # ── 1. idle cmux surfaces ──────────────────────────────────────────────────
  # Get surfaces from cmux tree --json; classify by events file mtime.
  local surfaces_json
  surfaces_json=$(cmux tree --json 2>/dev/null || printf '{"surfaces":[]}')

  while IFS= read -r surface_ref; do
    [[ -z "$surface_ref" ]] && continue
    # Find the events file for this surface by scanning worktree base
    local events_file=""
    if [[ -d "$worktree_base" ]]; then
      events_file=$(find "$worktree_base" -name ".cmux-events.jsonl" \
        -path "*/${surface_ref#surface:}/*" 2>/dev/null | head -1 || true)
    fi
    if [[ -n "$events_file" ]] && _is_stale "$events_file"; then
      idle_surfaces=$(printf '%s' "$idle_surfaces" | \
        python3 -c "import sys,json; a=json.load(sys.stdin); a.append('$surface_ref'); print(json.dumps(a))")
    fi
  done < <(printf '%s' "$surfaces_json" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); [print(s.get('id','')) for s in d.get('surfaces',[])]" 2>/dev/null || true)

  # ── 2. merged worktrees ────────────────────────────────────────────────────
  if [[ -d "$worktree_base" ]]; then
    for ticket_dir in "$worktree_base"/*/; do
      [[ -d "$ticket_dir" ]] || continue
      local ticket
      ticket=$(basename "$ticket_dir")
      local wt_path="$ticket_dir/cmux-tab-agents"
      [[ -d "$wt_path" ]] || continue

      local events_file="$wt_path/.cmux-events.jsonl"

      # Skip live (fresh events file) — v1 idleness heuristic
      if [[ -f "$events_file" ]] && ! _is_stale "$events_file"; then
        continue
      fi

      # Check if the PR for this ticket is merged
      if _pr_is_merged "$ticket"; then
        merged_worktrees=$(printf '%s' "$merged_worktrees" | \
          python3 -c "import sys,json; a=json.load(sys.stdin); a.append('$wt_path'); print(json.dumps(a))")
      fi
    done
  fi

  # ── 3. merged branches (no associated active worktree) ────────────────────
  # Walk git worktree list in the real repo; find branches matching merged tickets
  # whose worktree directory no longer exists.
  local repo_root
  repo_root=$(git -C "$(dirname "$(dirname "$(dirname "$(dirname "$0")")")")" rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -n "$repo_root" ]]; then
    while IFS= read -r branch; do
      [[ -z "$branch" ]] && continue
      local ticket
      ticket=$(printf '%s' "$branch" | grep -oE '[A-Z]+-[0-9]+|ISSUE-[0-9]+' | head -1 || true)
      [[ -z "$ticket" ]] && continue
      # Only include if no active worktree for that ticket
      local wt_for_ticket="$worktree_base/$ticket/cmux-tab-agents"
      [[ -d "$wt_for_ticket" ]] && continue
      if _pr_is_merged "$ticket"; then
        merged_branches=$(printf '%s' "$merged_branches" | \
          python3 -c "import sys,json; a=json.load(sys.stdin); a.append({'repo':'$repo_root','branch':'$branch','ticket':'$ticket'}); print(json.dumps(a))")
      fi
    done < <(git -C "$repo_root" branch --format='%(refname:short)' \
      --list 'feat/*' --list 'fix/*' --list 'chore/*' 2>/dev/null || true)
  fi

  # ── 4. stale agent streams ─────────────────────────────────────────────────
  # Agent JSONL files in agents_dir whose corresponding surface no longer exists.
  if [[ -d "$agents_dir" ]]; then
    local known_surfaces
    known_surfaces=$(printf '%s' "$surfaces_json" | \
      python3 -c "import sys,json; d=json.load(sys.stdin); [print(s.get('id','')) for s in d.get('surfaces',[])]" 2>/dev/null || true)
    for stream in "$agents_dir"/*.jsonl "$agents_dir"/**/*.jsonl; do
      [[ -f "$stream" ]] || continue
      local sid
      sid=$(grep -o '"surface_id":"[^"]*"' "$stream" | head -1 | sed 's/.*"surface_id":"//;s/".*//' || true)
      [[ -z "$sid" ]] && continue
      if ! printf '%s' "$known_surfaces" | grep -qF "$sid"; then
        stale_streams=$(printf '%s' "$stale_streams" | \
          python3 -c "import sys,json; a=json.load(sys.stdin); a.append('$stream'); print(json.dumps(a))")
      fi
    done
  fi

  # ── emit JSON ──────────────────────────────────────────────────────────────
  python3 -c "
import json, sys
print(json.dumps({
    'idle_surfaces': $(printf '%s' "$idle_surfaces"),
    'merged_worktrees': $(printf '%s' "$merged_worktrees"),
    'merged_branches': $(printf '%s' "$merged_branches"),
    'stale_streams': $(printf '%s' "$stale_streams"),
}, indent=2))
"

  # ── apply (if requested) ───────────────────────────────────────────────────
  if [[ "$apply" == true ]]; then
    printf '\n=== applying cleanup ===\n'

    # Parse JSON arrays into bash arrays via python.
    local -a surfaces=() worktrees=() streams=()
    while IFS= read -r item; do [[ -n "$item" ]] && surfaces+=("$item"); done < <(
      printf '%s' "$idle_surfaces" | python3 -c "import sys,json; [print(x) for x in json.load(sys.stdin)]"
    )
    while IFS= read -r item; do [[ -n "$item" ]] && worktrees+=("$item"); done < <(
      printf '%s' "$merged_worktrees" | python3 -c "import sys,json; [print(x) for x in json.load(sys.stdin)]"
    )
    while IFS= read -r item; do [[ -n "$item" ]] && streams+=("$item"); done < <(
      printf '%s' "$stale_streams" | python3 -c "import sys,json; [print(x) for x in json.load(sys.stdin)]"
    )

    if [[ "${#surfaces[@]}" -gt 0 ]]; then
      cmd_close_surfaces --apply "${surfaces[@]}"
    fi
    if [[ "${#worktrees[@]}" -gt 0 ]]; then
      cmd_remove_worktrees --apply "${worktrees[@]}"
    fi

    # merged_branches is a list of {repo,branch,ticket} objects — group by repo.
    while IFS=$'\t' read -r repo branch; do
      [[ -z "$repo" || -z "$branch" ]] && continue
      cmd_delete_branches --apply "$repo" "$branch"
    done < <(
      printf '%s' "$merged_branches" | python3 -c "
import sys, json
for b in json.load(sys.stdin):
    print(f\"{b.get('repo','')}\t{b.get('branch','')}\")
"
    )

    if [[ "${#streams[@]}" -gt 0 ]]; then
      cmd_prune_streams --apply "${streams[@]}"
    fi

    printf '=== applied: %d surfaces, %d worktrees, %d streams ===\n' \
      "${#surfaces[@]}" "${#worktrees[@]}" "${#streams[@]}"
  fi
}

# ── close-surfaces ─────────────────────────────────────────────────────────────

cmd_close_surfaces() {
  local apply=false
  local verbose=false
  local surfaces=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply)   apply=true;   shift ;;
      --verbose) verbose=true; shift ;;
      *) surfaces+=("$1"); shift ;;
    esac
  done

  if [[ "${#surfaces[@]}" -eq 0 ]]; then
    log "close-surfaces: no surfaces specified"
    return 0
  fi

  for ref in "${surfaces[@]}"; do
    if [[ "$apply" == true ]]; then
      log "Closing surface: $ref"
      [[ "$verbose" == true ]] && printf '[verbose] attempting close: %s\n' "$ref"
      if cmux close-surface --surface "$ref" 2>/dev/null; then
        [[ "$verbose" == true ]] && printf '[verbose] closed ok: %s\n' "$ref"
      else
        [[ "$verbose" == true ]] && printf '[verbose] close failed: %s\n' "$ref"
        log "  (could not close $ref)"
      fi
    else
      printf '[dry-run] would close surface: %s\n' "$ref"
      [[ "$verbose" == true ]] && printf '[verbose] candidate: %s\n' "$ref"
    fi
  done
}

# ── remove-worktrees ───────────────────────────────────────────────────────────

cmd_remove_worktrees() {
  local apply=false
  local paths=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply) apply=true; shift ;;
      *) paths+=("$1"); shift ;;
    esac
  done

  if [[ "${#paths[@]}" -eq 0 ]]; then
    log "remove-worktrees: no paths specified"
    return 0
  fi

  for wt in "${paths[@]}"; do
    if [[ "$apply" == true ]]; then
      log "Removing worktree: $wt"
      if [[ -d "$wt" ]]; then
        git worktree remove "$wt" 2>/dev/null || rm -rf "$wt"
        # Remove empty parent directory
        local parent
        parent=$(dirname "$wt")
        rmdir "$parent" 2>/dev/null || true
      else
        log "  (not found, skipping)"
      fi
    else
      printf '[dry-run] would remove worktree: %s\n' "$wt"
    fi
  done
}

# ── delete-branches ────────────────────────────────────────────────────────────

cmd_delete_branches() {
  local apply=false
  local repo=""
  local branches=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply) apply=true; shift ;;
      *)
        if [[ -z "$repo" ]]; then repo="$1"
        else branches+=("$1"); fi
        shift ;;
    esac
  done

  if [[ -z "$repo" ]]; then
    error "delete-branches requires <repo> as first non-flag argument"
  fi

  if [[ "${#branches[@]}" -eq 0 ]]; then
    log "delete-branches: no branches specified"
    return 0
  fi

  for branch in "${branches[@]}"; do
    if [[ "$apply" == true ]]; then
      log "Deleting branch: $branch"
      git -C "$repo" branch -d "$branch" 2>/dev/null || \
        log "  (could not delete $branch — may be unmerged; use -D to force)"
    else
      printf '[dry-run] would delete branch: %s (in %s)\n' "$branch" "$repo"
    fi
  done
}

# ── prune-streams ──────────────────────────────────────────────────────────────

cmd_prune_streams() {
  local apply=false
  local files=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply) apply=true; shift ;;
      *) files+=("$1"); shift ;;
    esac
  done

  if [[ "${#files[@]}" -eq 0 ]]; then
    log "prune-streams: no files specified"
    return 0
  fi

  for f in "${files[@]}"; do
    if [[ "$apply" == true ]]; then
      log "Removing stream: $f"
      rm -f "$f" || log "  (could not remove $f)"
    else
      printf '[dry-run] would prune stream: %s\n' "$f"
    fi
  done
}

# ── dispatch ───────────────────────────────────────────────────────────────────

[[ $# -eq 0 ]] && usage

SUBCMD="$1"; shift

case "$SUBCMD" in
  discover)         cmd_discover "$@" ;;
  close-surfaces)   cmd_close_surfaces "$@" ;;
  remove-worktrees) cmd_remove_worktrees "$@" ;;
  delete-branches)  cmd_delete_branches "$@" ;;
  prune-streams)    cmd_prune_streams "$@" ;;
  --help|-h)        usage ;;
  *)                error "Unknown subcommand: $SUBCMD"; usage ;;
esac

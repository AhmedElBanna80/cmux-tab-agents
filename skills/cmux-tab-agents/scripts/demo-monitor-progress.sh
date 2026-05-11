#!/usr/bin/env bash
# demo-monitor-progress.sh — demonstrates how a planner watches an implementer's
# progress stream using tail -f + Claude Code's Monitor tool.
#
# This script is DOCUMENTATION ONLY — it shows the pattern; it does not run
# in CI. The Monitor(...) calls below are pseudo-code illustrating what the
# planner would invoke in its own Claude session.
#
# EXPERIMENTAL — see SKILL.md "Progress event stream (experimental)" section.

# --- Emitter side (implementer runs this in its worktree) -------------------
#
# The implementer calls progress.sh at two instrumented points (boot + finish):
#
#   # At start of boot sequence (after pwd + git status succeed):
#   bash "{{SKILL_BASE}}/scripts/progress.sh" started 1 boot
#   # ... boot work ...
#   bash "{{SKILL_BASE}}/scripts/progress.sh" done 1
#
#   # Before finish-task.sh (Step 6):
#   bash "{{SKILL_BASE}}/scripts/progress.sh" started 6 finish
#   bash "{{SKILL_BASE}}/scripts/finish-task.sh" --mode pr --worktree <WORKTREE>
#   bash "{{SKILL_BASE}}/scripts/progress.sh" done 6
#
# Each call appends one JSONL line to <WORKTREE>/.cmux-progress.jsonl:
#   {"v":1,"ts":"2026-05-11T10:00:00Z","src":"implementer","sid":"...","kind":"started","name":"boot","payload":{"step":1}}
#   {"v":1,"ts":"2026-05-11T10:00:05Z","src":"implementer","sid":"...","kind":"done","name":"boot","payload":{"step":1}}

# --- Subscriber side (planner opens a background tail shell) ----------------
#
# STEP 1: Open a long-lived tail shell (do this once per task):
#
#   WORKTREE="/path/to/worktree"
#   PROGRESS="$WORKTREE/.cmux-progress.jsonl"
#   touch "$PROGRESS"                      # ensure file exists before tail starts
#   tail -f "$PROGRESS"                    # keep this shell alive (Bash background)
#   # → note the shellId returned, e.g. "shell-42"
#
# STEP 2: Use Monitor to wait for specific events:
#
#   # Wait until boot is done (implementer finished its boot sequence):
#   Monitor(shellId="shell-42", until='"kind":"done".*"name":"boot"', timeout=60)
#
#   # Wait until finish is started (implementer is about to call finish-task.sh):
#   Monitor(shellId="shell-42", until='"kind":"started".*"name":"finish"', timeout=600)
#
#   # Wait until finish is done (PR opened / merge complete):
#   Monitor(shellId="shell-42", until='"kind":"done".*"name":"finish"', timeout=60)
#
# The same tail shell stays alive across all Monitor calls — no double-polling.
# When the task is fully done, kill the tail shell to clean up:
#
#   kill <tail-pid>   # or close the background shell via cmux

# --- Predicate cheat-sheet --------------------------------------------------
#
#   Boot started:     '"kind":"started".*"name":"boot"'
#   Boot done:        '"kind":"done".*"name":"boot"'
#   Finish started:   '"kind":"started".*"name":"finish"'
#   Finish done:      '"kind":"done".*"name":"finish"'
#   Any step started: '"kind":"started"'
#   Any step done:    '"kind":"done"'

printf 'demo-monitor-progress.sh: documentation only — see inline comments\n'
exit 0

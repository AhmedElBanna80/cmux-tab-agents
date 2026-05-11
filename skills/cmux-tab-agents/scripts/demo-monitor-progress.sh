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
# The implementer calls progress.sh at all step boundaries; reviewers call it too.
#
#   # Step 1 — boot:
#   bash "{{SKILL_BASE}}/scripts/progress.sh" started 1 boot
#   # ... boot work ...
#   bash "{{SKILL_BASE}}/scripts/progress.sh" done 1
#
#   # Step 2 — spec dispatch:
#   bash "{{SKILL_BASE}}/scripts/progress.sh" started 2 spec-dispatch
#   # ... dispatch spec-reviewer, wait for verdict ...
#   bash "{{SKILL_BASE}}/scripts/progress.sh" done 2
#
#   # Step 3 — spec fix round (per iteration):
#   bash "{{SKILL_BASE}}/scripts/progress.sh" started 3 spec-fix-round-1
#   # ... fix and commit ...
#   bash "{{SKILL_BASE}}/scripts/progress.sh" done 3
#
#   # Step 4 — code dispatch:
#   bash "{{SKILL_BASE}}/scripts/progress.sh" started 4 code-dispatch
#   # ... dispatch code-reviewer, wait for verdict ...
#   bash "{{SKILL_BASE}}/scripts/progress.sh" done 4
#
#   # Step 5 — code fix round (per iteration):
#   bash "{{SKILL_BASE}}/scripts/progress.sh" started 5 code-fix-round-1
#   # ... fix and commit ...
#   bash "{{SKILL_BASE}}/scripts/progress.sh" done 5
#
#   # Step 6 — finish:
#   bash "{{SKILL_BASE}}/scripts/progress.sh" started 6 finish
#   bash "{{SKILL_BASE}}/scripts/finish-task.sh" --mode pr --worktree <WORKTREE>
#   bash "{{SKILL_BASE}}/scripts/progress.sh" done 6
#   bash "{{SKILL_BASE}}/scripts/progress.sh" terminal DONE
#
#   # Reviewers emit once each (with --role flag):
#   bash "{{SKILL_BASE}}/scripts/progress.sh" --role spec-reviewer started review-began
#   bash "{{SKILL_BASE}}/scripts/progress.sh" --role spec-reviewer done review-began verdict=APPROVED
#
# Each call appends one JSONL line to <WORKTREE>/.cmux-progress.jsonl:
#   {"v":1,"ts":"...","src":"implementer","sid":"...","kind":"started","name":"boot","agent_role":"implementer","payload":{"step":"1","agent_role":"implementer"}}
#   {"v":1,"ts":"...","src":"spec","sid":"...","kind":"started","name":"review-began","agent_role":"spec-reviewer","payload":{"step":"review-began","agent_role":"spec-reviewer"}}

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
#   Boot started:           '"kind":"started".*"name":"boot"'
#   Boot done:              '"kind":"done".*"name":"boot"'
#   Spec dispatch started:  '"kind":"started".*"name":"spec-dispatch"'
#   Spec dispatch done:     '"kind":"done".*"name":"spec-dispatch"'
#   Spec fix round:         '"kind":"started".*"name":"spec-fix-round-'
#   Spec review started:    '"src":"spec".*"name":"review-began"'
#   Spec review done:       '"src":"spec".*"kind":"done".*"name":"review-began"'
#   Code dispatch started:  '"kind":"started".*"name":"code-dispatch"'
#   Code dispatch done:     '"kind":"done".*"name":"code-dispatch"'  (step:5:done)
#   Code fix round:         '"kind":"started".*"name":"code-fix-round-'
#   Code review started:    '"src":"code".*"name":"review-began"'
#   Code review done:       '"src":"code".*"kind":"done".*"name":"review-began"'
#   Finish started:         '"kind":"started".*"name":"finish"'
#   Finish done:            '"kind":"done".*"name":"finish"'
#   Terminal DONE:          '"kind":"terminal".*"name":"DONE"'
#   Terminal BLOCKED:       '"kind":"terminal".*"name":"BLOCKED"'
#   Any step started:       '"kind":"started"'
#   Any step done:          '"kind":"done"'
#   By role (implementer):  '"agent_role":"implementer"'
#   By role (spec):         '"agent_role":"spec-reviewer"'
#   By role (code):         '"agent_role":"code-reviewer"'

printf 'demo-monitor-progress.sh: documentation only — see inline comments\n'
exit 0

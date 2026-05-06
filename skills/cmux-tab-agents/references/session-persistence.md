# Session Persistence with crex

This document explains how tab-agents use **crex** (cmux-resurrect) to persist workspace state across session boundaries, enabling resumable 3-phase review cycles without zombie tabs.

## The Problem

Long-running review cycles are vulnerable to interruptions:
- Network disconnections
- Process crashes
- Deliberate session exits (Ctrl+C, `/clear`, etc.)
- Terminal emulator crashes

When a tab-agent exits unexpectedly, its environment is lost — working directory, uncommitted changes (in memory), active processes, and CMux layout all vanish. If the next reviewer needs to inspect or continue from that state, they face a cold restart.

## The Solution: crex (cmux-resurrect)

**crex** is a CMux plugin that snapshots workspace state (tabs, panes, layouts, working directories) to disk with a timestamp. On the next CMux launch, restoring the snapshot recreates the exact environment.

### Installation

```bash
brew install drolosoft/tap/crex
```

### Core Commands

```bash
# Save workspace with timestamp
crex save "$(date +%Y%m%d-%H%M%S)"  # creates 20260506-143022

# Restore workspace from a saved timestamp
crex restore 20260506-143022

# List saved workspaces
crex list
```

## Integration with tab-agents

### Implementer (save phase)

After completing implementation and dispatching reviewers, the implementer saves its workspace:

```bash
crex save "$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
```

This snapshots:
- All CMux tabs and panes (implementer, spec-reviewer dispatch, code-reviewer dispatch, planner communication)
- Working directory state
- Uncommitted files (via CMux's working dir capture)
- Git status

**Idempotency:** Running `crex save` multiple times overwrites with the latest timestamp. Safe to call before exit.

**Error handling:** `|| true` means crex absence is not fatal — the workflow continues without snapshots (graceful degradation).

### Spec-reviewer (restore on ISSUES_FOUND)

If the spec-reviewer finds issues and needs to investigate the implementer's environment:

```bash
crex restore 20260506-143022  # restore implementer's saved workspace
# Now can inspect tabs, re-run commands, review uncommitted state
```

Common investigations:
- Verify test output actually shows the test failing first
- Check uncommitted WIP files
- Re-run verification commands with different settings
- Trace through the Git history in the implementer's working context

**Optionality:** Spec-reviewer may not need to restore — only if they want to retrace steps. Most issues can be surfaced from code review alone.

### Code-reviewer (zombie tab detection)

As the final reviewer in the 3-phase cycle, code-reviewer monitors for orphaned tabs:

```bash
cmux list-windows  # check for stale tabs from previous phases
```

If zombie tabs exist (tabs that completed their phase but remain idle):
- Document in result file as a concern
- Implementer will investigate in their next round (if ISSUES_FOUND)
- On APPROVED, planner handles final cleanup

**Responsibility boundary:** Code-reviewer reports; implementer or planner cleans up.

## Planner integration

The planner configures the auto-save hook in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "crex save $(date +%Y%m%d-%H%M%S) 2>/dev/null || true",
            "statusMessage": "Saving CMux workspace..."
          }
        ]
      }
    ]
  }
}
```

**When it fires:** On every Claude session stop (Ctrl+C, `/clear`, exit, etc.) — automatically saves the workspace without user intervention.

**Naming:** Timestamp (`20260506-143022`) is readable and sorts chronologically. Easy to identify the most recent snapshot for restoration.

## Workflow Example: 3-phase cycle with crex

```
Implementer Tab (Task A)
├─ Implement feature
├─ Run TDD tests
├─ Dispatch spec-reviewer → surface:42
├─ Implementer idled, waiting for review
├─ Session ends (user closes terminal)
└─ crex save 20260506-143022
   └─ Snapshots: all tabs, working dirs, git state

Spec-reviewer Tab (Task A, resumed)
├─ Session restored via crex restore 20260506-143022
├─ Reviews code (can see implementer's environment)
├─ Finds ISSUES_FOUND
├─ Pushes back to implementer

Implementer Tab (resumed)
├─ Reads ISSUES_FOUND
├─ Session still has old state? Can optionally restore via crex
├─ Fixes issues (TDD)
├─ crex save 20260506-143045 (new snapshot for updated state)
├─ Re-dispatches spec-reviewer

Spec-reviewer Tab (second round)
├─ Reviews fixes
├─ Approves
├─ Dispatches code-reviewer

Code-reviewer Tab
├─ Reviews code quality
├─ Checks for zombie tabs (from implementer/spec phases)
├─ Approves

Finish
├─ Implementer runs finish-task.sh
└─ Planner cleans up worktree if needed
```

## Limitations and assumptions

- **Crex snapshots CMux, not Git state heavily** — result files survive (`.cmux-*.md` are on disk), but uncommitted code changes in the editor are only preserved if the editor auto-saves or CMux captures working-dir state.
- **No automatic restoration** — planner must explicitly call `crex restore <timestamp>`. Timestamps are human-readable but require knowing which snapshot to restore.
- **Worktree persists independently** — Git state in the worktree is durable (committed or staged). Crex is for UI/layout restoration, not code recovery.

## FAQ

**Q: Is crex required?**
A: No. Tab-agents have `|| true` guards, so missing crex is graceful. The workflow continues without session snapshots — just less resumable.

**Q: What if crex list shows old snapshots from failed tasks?**
A: Safe to delete stale snapshots manually: `rm -rf ~/.crex/<timestamp>`. Only the most recent snapshot for each task matters.

**Q: Can reviewers edit code via restored crex?**
A: Not recommended. Reviewers should only inspect, not modify. Code changes should flow through the implementer (via ISSUES_FOUND feedback). Editing via restored crex could lead to inconsistent git history.

**Q: Zombie tabs left behind — who cleans up?**
A: Code-reviewer reports them; implementer or planner cleans them up manually or via tmux/CMux commands. Not automated.

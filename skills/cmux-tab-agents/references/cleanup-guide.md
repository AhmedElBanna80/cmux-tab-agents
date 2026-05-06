# Cleanup Guide

After a task completes (implementer → spec-reviewer → code-reviewer → task-result DONE), use `done-cleanup.sh` to remove crex sessions, kill agent tabs, and delete worktrees.

## Quick Start

### Clean a single completed task
```bash
~/.claude/skills/cmux-tab-agents/scripts/done-cleanup.sh --ticket CREX-FULL-TEST-001
```

### Clean all completed tasks
```bash
~/.claude/skills/cmux-tab-agents/scripts/done-cleanup.sh --all
```

### Keep the worktree, just cleanup sessions and tabs
```bash
~/.claude/skills/cmux-tab-agents/scripts/done-cleanup.sh --ticket CREX-FULL-TEST-001 --keep-worktree
```

### Dry-run (see what would be deleted)
```bash
~/.claude/skills/cmux-tab-agents/scripts/done-cleanup.sh --ticket CREX-FULL-TEST-001 --dry-run
```

---

## What Gets Removed

### 1. Crex Sessions
Removes any crex session files associated with the task. These are session snapshots saved by `crex save` during implementer completion.

**Location:** Managed by crex (cmux-resurrect)  
**Command:** `crex list` / `crex delete`

### 2. Agent Tabs (Surfaces)
Kills any remaining cmux surfaces/tabs for the task's agents:
- `<TICKET>-implementer`
- `<TICKET>-spec-reviewer`
- `<TICKET>-code-reviewer`

**Location:** cmux tab bar / sidebar  
**Command:** `cmux send ... exit`

### 3. Worktrees
Removes the git worktree directory and cleans up empty parent directories.

**Location:** `/Users/banna/POC/worktrees/cmux-tab-agents/<TICKET>/`  
**Command:** `git worktree remove`

---

## When to Use

### After Task Completes (Status: DONE)
Once `.cmux-task-result.md` shows `status: DONE`, the task is ready for cleanup:

```bash
# Check task status
cat /Users/banna/POC/worktrees/cmux-tab-agents/<TICKET>/cmux-tab-agents/.cmux-task-result.md | grep status

# If status: DONE, cleanup
done-cleanup.sh --ticket <TICKET>
```

### Batch Cleanup (Housekeeping)
Run `--all` periodically to clean up all completed tasks:

```bash
done-cleanup.sh --all
```

This scans all worktrees and cleans only those with `status: DONE` in their task-result file.

---

## Keeping Worktrees for Reference

If you want to keep a worktree for code inspection or historical reference after cleanup:

```bash
done-cleanup.sh --ticket CREX-FULL-TEST-001 --keep-worktree
```

This removes sessions and tabs but preserves the git worktree and its commit history. You can still:
- Review commits: `git log` in the worktree
- Check out the branch: `git checkout feat/<TICKET>/<slug>`
- Inspect code: browse files in the worktree directory

---

## Troubleshooting

### "crex not installed"
The script gracefully skips crex session cleanup if crex is not available.

**Fix:** Install crex if you want session cleanup:
```bash
brew install crex  # macOS
# or via patchoutech-plugins (auto-installs with plugin)
```

### "Could not remove worktree"
The worktree is still in use by another process (e.g., a tab is still open).

**Fix:** Manually kill the tab first:
```bash
cmux send --surface <SURFACE_ID> "exit"
sleep 1
done-cleanup.sh --ticket <TICKET>
```

### "Worktree directory not found"
Already removed or the task uses a different worktree base path.

**Fix:** No action needed — the cleanup will skip and continue with other cleanup tasks.

---

## Automation

Add to your post-task workflow (e.g., shell alias or script):

```bash
# ~/.bashrc or ~/.zshrc
alias task-done='done-cleanup.sh'

# Or in a script after task-result.md is created:
if grep -q "status: DONE" "$RESULT_FILE"; then
  done-cleanup.sh --ticket "$TICKET"
fi
```

---

## See Also

- `references/dispatch-reference.md` — Dispatching tasks
- `references/finishing.md` — Finish modes (keep/pr/merge)
- `references/session-persistence.md` — Crex session management

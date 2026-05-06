
## Task Completion & Cleanup

After the full 3-phase cycle completes (implementer → spec-reviewer → code-reviewer → `.cmux-task-result.md` with `status: DONE`), use the cleanup command to remove crex sessions, kill agent tabs, and delete worktrees.

### Cleanup a Completed Task

```bash
~/.claude/skills/cmux-tab-agents/scripts/done-cleanup.sh --ticket <TICKET>
```

This removes:
- Crex session snapshots
- Agent tabs from cmux sidebar (implementer, spec-reviewer, code-reviewer)
- Git worktree directory

### Options

**Keep worktree for code inspection:**
```bash
done-cleanup.sh --ticket <TICKET> --keep-worktree
```

**Dry-run to preview:**
```bash
done-cleanup.sh --ticket <TICKET> --dry-run
```

**Batch cleanup (all completed tasks):**
```bash
done-cleanup.sh --all
```

### When to Cleanup

- After task-result file shows `status: DONE`
- Before dispatching next task (keeps sidebar clean)
- Periodically for workspace hygiene

See `references/cleanup-guide.md` for detailed troubleshooting.

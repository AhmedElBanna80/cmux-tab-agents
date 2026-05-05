# cmux-tab-agents operational guide

## Setup

### Consumer repo .gitignore

The dispatcher automatically injects `.cmux-*` and `.cmux-tab-prompt-*.md` patterns into the worktree's `.gitignore` when creating a new worktree. This prevents tab-agent result files from being accidentally committed.

**Important:** Do not run `git add -A` before dispatch has completed — the pattern injection must run first. If you need to stage changes, stage specific files instead:

```bash
git add path/to/specific/file  # OK: explicit files
git add .                      # RISKY: before dispatcher has run
```

Once dispatch runs (lines 1a in `_dispatch_common.sh`), the `.gitignore` is populated and subsequent operations are safe. The `make lint` check verifies `.cmux-*` is in `.gitignore`.

## Edge cases

### Worktree path exists but is not a git worktree

`ensure-worktree.sh` exits 1 with a clear message. The skill refuses to clobber unknown content. Action: investigate manually (the directory may be from a previous attempt or unrelated work). Remove or rename, then retry.

### `--dangerously-skip-permissions` is real but bounded

Tab-agents run with `--dangerously-skip-permissions` because the worktree is sandboxed and there's no human in the loop for permission prompts. The seed prompt forbids edits outside the worktree and forbids hook bypass. The blast radius is one disposable worktree.

### Tab-agent crashes mid-task

`poll-result.sh` times out. Treat as a soft `BLOCKED`. Read the tab's pane (`cmux capture-pane --surface <ref> --scrollback`) for context, then either re-dispatch or escalate.

## Integration with other skills

- **Before** invoking this skill, the planner uses `superpowers:writing-plans` (or its own judgment) to produce the sub-task list.
- **After** all sub-tasks are done, the planner runs `superpowers:finishing-a-development-branch` *per sub-task* — each sub-task has its own branch in its own worktree, so each integrates independently.
- The `superpowers:test-driven-development` and `superpowers:verification-before-completion` discipline is **not** invoked at runtime by tab-agents — it is **embedded verbatim** in the seed prompts (see `prompts/implementer-tab-prompt.md` and the reviewer prompts). This is intentional: tab-agents run in fresh `claude` processes that may not have the superpowers plugin loaded, so the discipline must be self-contained.

---
# This is the /cmux-tab-agents:cleanup command.
# It guides the planner through discovering and removing stale cmux state
# (surfaces, worktrees, branches, agent streams) for merged PRs.
---

# /cmux-tab-agents:cleanup

Reconcile open cmux surfaces, worktrees, git branches, and agent event streams
against merged GitHub PRs, then offer to remove dead state — category by
category, with dry-run preview and per-category confirmation.

**Safety:** Default is dry-run. Nothing is deleted until you explicitly approve
each category. `git branch -d` only (refuses unmerged). `git worktree remove`
only (no `--force`). The planner's own surface and the agents pane are never
touched.

---

## How it works

1. **Discover** — runs `cleanup-helper.sh discover` to cross-reference:
   - Idle cmux surfaces (events file older than 30 min)
   - Worktrees whose branch's PR is merged on GitHub
   - Local branches with merged PRs and no associated active worktree
   - Per-agent JSONL stream files whose surface no longer exists

2. **Report** — shows you a structured dry-run summary via `AskUserQuestion`,
   one category at a time.

3. **Confirm** — you approve or skip each category independently.

4. **Apply** — for each approved category, calls the appropriate
   `cleanup-helper.sh` subcommand with `--apply`.

5. **Summarize** — prints what was cleaned and what was kept.

---

## Before you begin

Run the following to see what would be cleaned:

```bash
~/.claude/skills/cmux-tab-agents/scripts/cleanup-helper.sh discover
```

The output is a JSON object with four arrays:
- `idle_surfaces` — surface refs
- `merged_worktrees` — worktree directory paths
- `merged_branches` — `{repo, branch, ticket}` objects
- `stale_streams` — JSONL file paths

---

## Step-by-step execution

Now, begin executing the cleanup per the instructions below. Ask the user using
`AskUserQuestion` (once per category) and apply choices immediately before
moving to the next.

### Step 1 — Discover

Run:

```bash
DISCOVER_JSON=$(~/.claude/skills/cmux-tab-agents/scripts/cleanup-helper.sh discover 2>/dev/null)
```

Parse the four arrays. If all are empty, tell the user nothing to clean and
stop.

### Step 2 — Idle surfaces

If `idle_surfaces` is non-empty, use `AskUserQuestion`:

> **Idle cmux surfaces**
> The following surfaces have no recent agent activity (events file > 30 min old).
> Closing them frees sidebar space.
>
> `<list the surface refs>`
>
> Close these surfaces?

Options: **Yes, close them** / **Skip**

If approved:
```bash
~/.claude/skills/cmux-tab-agents/scripts/cleanup-helper.sh close-surfaces --apply \
  <surface_ref_1> <surface_ref_2> ...
```

### Step 3 — Merged worktrees

If `merged_worktrees` is non-empty, use `AskUserQuestion`:

> **Stale worktrees (PR merged)**
> The following worktree directories belong to branches whose PRs are merged.
> Removing them frees disk space.
>
> `<list the paths>`
>
> Remove these worktrees?

Options: **Yes, remove them** / **Skip**

If approved:
```bash
~/.claude/skills/cmux-tab-agents/scripts/cleanup-helper.sh remove-worktrees --apply \
  <path_1> <path_2> ...
```

### Step 4 — Merged branches

If `merged_branches` is non-empty, use `AskUserQuestion`:

> **Local branches (PR merged, no active worktree)**
> The following local branches have merged PRs and no active worktree.
> Deleting them (safe `git branch -d`) cleans up local refs.
>
> `<list: branch (repo)>`
>
> Delete these branches?

Options: **Yes, delete them** / **Skip**

If approved, for each unique repo, call:
```bash
~/.claude/skills/cmux-tab-agents/scripts/cleanup-helper.sh delete-branches --apply \
  <repo_path> <branch_1> <branch_2> ...
```

If `git branch -d` refuses (unmerged branch), report it as skipped — never
use `-D` without asking the user explicitly.

### Step 5 — Stale agent streams

If `stale_streams` is non-empty, use `AskUserQuestion`:

> **Orphaned agent event streams**
> The following JSONL files have no corresponding live surface.
>
> `<list the paths>`
>
> Prune these stream files?

Options: **Yes, prune them** / **Skip**

If approved:
```bash
~/.claude/skills/cmux-tab-agents/scripts/cleanup-helper.sh prune-streams --apply \
  <path_1> <path_2> ...
```

### Step 6 — Summary

Print a brief summary:

```
Cleanup complete.
  Closed surfaces:  N
  Removed worktrees: N
  Deleted branches:  N
  Pruned streams:    N
  Skipped: <list any skipped categories>
```

---

## Running again (idempotency)

This command is idempotent. Running it again after a cleanup returns empty
lists for any categories you already applied. It is safe to run periodically
as housekeeping.

---

## See also

- `references/cleanup-guide.md` — Agent-side `done-cleanup.sh` and the
  difference from this planner-side command.
- `scripts/cleanup-helper.sh` — The helper script that does the heavy lifting.
- `scripts/done-cleanup.sh` — Post-task cleanup for individual completed tasks.
